DR Test: IPA Domain Down
Date: 2026-04-15 to 2026-04-16
Result: PASS + 4 FIXES APPLIED
_____________________________________________________________________

[Info]
Domain: DNS / FreeIPA / Vault / Kubernetes / Ansible
Environment: DEV — full stack (k8s cluster, vault cluster, FreeIPA, ansible)
Triggered by: FreeIPA is the DNS authority for lab.local — what happens
  to everything when it goes down?

_____________________________________________________________________

[Planned Scope]

Stop FreeIPA server entirely and observe what breaks across the infra.
FreeIPA serves DNS for all .lab.local hostnames, Kerberos auth, and
SSSD identity. Expecting DNS-dependent services to fail. Also expecting
domain users who haven't logged in recently (no cached SSSD credentials
on that node) to be locked out — SSSD can't reach IPA to authenticate.
Users with cached creds can still login even with domain down.

Components expected to be affected: Vault agent (DNS-based auth),
WordPress (external API calls), Ansible (SSSD lookups), any pod
needing to resolve .lab.local names

_____________________________________________________________________

[Pre-State]

All FreeIPA services running (Directory, krb5kdc, kadmin, named, httpd).
K8s cluster healthy (6 nodes Ready). Vault unsealed, HA active, seal
type awskms.

_____________________________________________________________________

[Test 1.1 — Stop FreeIPA]

Action:
  ```
  ssh root@freeipa 'ipactl stop'
  ```

What happened:
  - Vault agent sidecars: started failing DNS lookups within ~1 minute
    ```
    dial tcp: lookup vault.lab.local on 10.96.0.10:53: server misbehaving
    ```
    Exponential backoff: 820ms → 1.5s → 2.5s → 4.3s. After ~10 min,
    vault-agent containers crash (exit code 1).

  - WordPress: pages loading in 4-12s instead of <1s. Not broken but
    painfully slow. External API calls (Gravatar, api.wordpress.org)
    timing out because DNS can't resolve external domains.

  - Ansible: 28-34 seconds per operation (expected <5s). Each SSH
    connection triggers 2 SSSD lookups via KnownHostsCommand
    (/usr/bin/sss_ssh_knownhosts), ~2s timeout each, 7-8 connections
    per module = ~28s wasted.

  - Existing pods with cached secrets: WORKS — already authenticated,
    don't need DNS right now.

  - K8s cluster operations: WORKS — kubelet uses IPs internally.

  - Vault cluster (internal): WORKS — Raft uses IPs, /etc/hosts has entries.

Cascade:
  IPA down → DNS gone for .lab.local → vault agent can't resolve
  vault.lab.local → new pods can't get secrets → pods stuck in Init →
  meanwhile WordPress slow (external DNS timeout), Ansible slow (SSSD)

_____________________________________________________________________

[Test 1.2 — Trigger pod restart during outage]

Why this test: existing pods survive, but what about new pods?

Action:
  ```
  kubectl rollout restart deployment wordpress -n apps
  ```

What happened:
  - New pod stuck in Init:1/2 for 29 minutes
    ```
    wordpress-7b8c7d879-xbzfr    0/2     Init:1/2   0   29m
    ```
  - vault-agent-init couldn't resolve vault.lab.local → blocked forever
  - Old pods kept running (rolling update strategy protected availability)

What this tells me:
  **Critical finding: node /etc/hosts does NOT help pods.** The node can
  resolve vault.lab.local via /etc/hosts, but pods use CoreDNS (10.96.0.10)
  which doesn't read /etc/hosts. CoreDNS forwards to the node's
  /etc/resolv.conf which points to IPA (down).

  Evidence:
  ```
  # From NODE — works via /etc/hosts
  ping vault.lab.local → 10.0.62.100 ✓

  # From POD — fails via CoreDNS
  lookup vault.lab.local on 10.96.0.10:53: server misbehaving ✗
  ```

  Operational rule: during IPA outage, DO NOT restart/scale/delete pods
  that use Vault secrets. They will block on init and never come up.

_____________________________________________________________________

[Test 1.3 — Vault auto-unseal during IPA outage]

Why this test: Vault seals use AWS KMS. If DNS is down, can Vault
  still reach the KMS endpoint to unseal?

Action:
  Applied DNS fallback fix first (see below), then rebooted all 3 vault nodes
  while IPA was still down.

What happened:
  - google.com resolved via 8.8.8.8 fallback → AWS KMS endpoint reachable
  - Vault unsealed automatically via awskms
    ```
    vault status → Sealed: false, Seal Type: awskms
    ```

What this tells me:
  The hybrid cloud dependency (on-prem Vault → AWS KMS) survives IPA outage
  as long as nodes have DNS fallback for external resolution. Without the
  fallback, Vault would stay sealed after a reboot during IPA outage —
  that would cascade into every pod needing secrets.

_____________________________________________________________________

[Fixes Applied]

Fix 1 — CoreDNS hosts plugin (TS-K8S-033):
  Added static entries for vault.lab.local and k8s.lab.local directly
  in CoreDNS config. Pods can now resolve these names without IPA.
  ```
  hosts {
      10.0.62.100 vault.lab.local vault
      10.0.61.100 k8s.lab.local k8s
      fallthrough
  }
  ```
  Verified: `kubectl run test-dns --rm -it --image=busybox -- nslookup vault.lab.local`
  → 10.0.62.100 ✓

Fix 2 — Node DNS fallback (TS-LNX-003):
  FreeIPA client enrollment creates /etc/NetworkManager/conf.d/zzz-ipa.conf
  with only IPA DNS. The "zzz-" prefix makes it load last, overriding
  everything. Modified to include 8.8.8.8 as fallback.
  Applied via Ansible playbook to all IPA-enrolled nodes.

Fix 3 — Ansible SSH fix (TS-IDN-009):
  Added `KnownHostsCommand=none` to inventory. Ansible operations went
  from 34s → 3s during IPA outage.

Fix 4 — WordPress external DNS:
  Resolved by Fix 2 (node DNS fallback). CoreDNS forwards external
  queries to node's resolv.conf which now has 8.8.8.8. WordPress
  external API calls resolve again.

_____________________________________________________________________

[Recovery]

  ```
  ssh root@freeipa 'ipactl start'
  ```
  Stuck pods recovered within seconds after IPA restoration. Vault agents
  re-authenticated, init containers completed, pods reached 2/2 Running.

_____________________________________________________________________

[Findings]

1. FreeIPA is a hidden SPOF for the entire stack through DNS. Everything
   uses .lab.local names — vault, k8s API, node hostnames. When IPA dies,
   DNS dies, and the blast radius is wider than expected.

2. Node /etc/hosts and pod DNS are completely separate. CoreDNS doesn't
   read node /etc/hosts. This is the most non-obvious finding — you can
   fix DNS on the node and pods still fail. The CoreDNS hosts plugin is
   the pod-level equivalent of /etc/hosts.

3. Existing pods survive IPA outage (cached secrets). New pods don't
   (vault-agent-init blocks on DNS). Rolling update strategy saved us —
   old pods kept serving while new pods were stuck.

4. The hybrid cloud dependency chain (Vault → AWS KMS → external DNS)
   requires fallback DNS on nodes. Without it, a local IPA outage could
   prevent Vault from unsealing, which cascades into every secret-dependent
   workload.

5. SSSD/Kerberos timeouts are hidden performance killers. The 28s Ansible
   delay wasn't a failure — it was SSSD retrying IPA for each SSH
   connection. Silent degradation, not a crash.

_____________________________________________________________________

[Planned Next]

- Test node failure during IPA outage — can pods reschedule without
  vault DNS resolution?
- Consider IPA replica server for HA

_____________________________________________________________________

[References]

- TS-K8S-033 — Vault Agent DNS failure + pod blocking
- TS-K8S-034 — WordPress external DNS slowness
- TS-K8S-035 — Pod restart investigation (vault-agent vs app)
- TS-IDN-009 — Ansible SSSD KnownHostsCommand timeout
- TS-LNX-003 — Linux nodes DNS fallback
- kubernetes/dev/deployments/infrastructure/coredns/coredns-custom.yaml
- playbooks/freeipa/dns_fallback.yml
