# TS-K8S-033 | 2026-04-16 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / Vault Agent / CoreDNS / FreeIPA DNS
Sub-techs: Vault Agent sidecar, vault-agent-init, CoreDNS hosts plugin,
           DNS resolution chain, rolling update protection
Environment: DEV k8s cluster | lab.local domain | FreeIPA DNS at 10.0.60.10
Discovered during: IPA Domain Down DR Test (Part 2)
Related: TS-IDN-009 (Ansible SSSD KnownHostsCommand timeout),
         TS-K8S-034 (WordPress external DNS slowness)
Re-opened: No

_____________________________________________________________________

[Issue Description]
Two related problems when FreeIPA DNS is unavailable:

**Issue A:** Running Vault Agent sidecars crash after ~10 minutes of DNS failure
due to retry exhaustion.

**Issue B (Critical):** New pods with Vault Agent init containers can't start at
all — `vault-agent-init` can't authenticate to Vault, blocking pod startup
indefinitely.

_____________________________________________________________________

[Analysis]

# Issue A: Running Vault Agent sidecars crash

I stopped IPA and watched what happened:

```
[root@ansible dev]# ssh root@freeipa 'ipactl stop'
ipa: INFO: The ipactl command was successful
[root@ansible dev]# date
Wed Apr 15 10:00:49 PM EET 2026
```

Immediate Vault Agent errors (T+0 to T+2 minutes):
```
2026-04-15T20:01:33.700Z [WARN]  agent: (view) vault.read(secret/data/wordpress/config):
  Get "https://vault.lab.local:8200/v1/secret/data/wordpress/config":
  dial tcp: lookup vault.lab.local on 10.96.0.10:53: server misbehaving (retry attempt 1 after "250ms")
2026-04-15T20:01:58.328Z [WARN]  ... (retry attempt 2 after "500ms")
2026-04-15T20:02:20.006Z [WARN]  ... (retry attempt 3 after "1s")
```

Exponential backoff — retries hit max at 1 minute intervals:
```
2026-04-15T20:07:00.639Z [WARN]  ... (retry attempt 10 after "1m0s")
2026-04-15T20:08:18.875Z [WARN]  ... (retry attempt 11 after "1m0s")
2026-04-15T20:09:43.342Z [WARN]  ... (retry attempt 12 after "1m0s")
```

All Vault Agent sidecars crashed with exit code 1 after ~10 minutes:
```
=== mariadb-0 (database) ===
vault-agent: exitCode=1 finished=2026-04-15T20:12:04Z

=== wordpress-56bf4b697d-87tvx (apps) ===
vault-agent: exitCode=1 finished=2026-04-15T20:11:07Z

=== wordpress-56bf4b697d-8k8jc (apps) ===
vault-agent: exitCode=1 finished=2026-04-15T20:14:52Z

=== wordpress-56bf4b697d-vxc69 (apps) ===
vault-agent: exitCode=1 finished=2026-04-15T20:15:54Z
```

Grafana pods (3 replicas) and remediation pod also crashed:
```
Pod: kube-prometheus-stack-grafana-5f6554dcf5-lrvqq
  vault-agent: exitCode=1 finished=2026-04-15T20:12:16Z

Pod: remediation-56bdddfcd7-t8fvv
  vault-agent: exitCode=1 finished=2026-04-15T20:14:25Z
```

# Issue B: New pods can't start

I tried a rollout restart while IPA was still down:
```
kubectl rollout restart deployment wordpress -n apps
```

New pod stuck in Init:1/2 for 29 minutes:
```
NAME                         READY   STATUS     RESTARTS      AGE
wordpress-56bf4b697d-87tvx   2/2     Running    1 (37m ago)   61m
wordpress-56bf4b697d-8k8jc   2/2     Running    1 (33m ago)   61m
wordpress-56bf4b697d-vxc69   2/2     Running    1 (32m ago)   61m
wordpress-7b8c7d879-xbzfr    0/2     Init:1/2   0             2m16s  ← STUCK
```

vault-agent-init logs — authentication failing on every attempt:
```
2026-04-15T20:46:43.437Z [ERROR] agent.auth.handler: error authenticating:
  error="Put \"https://vault.lab.local:8200/v1/auth/kubernetes/login\":
  dial tcp: lookup vault.lab.local on 10.96.0.10:53: server misbehaving" backoff=820ms
2026-04-15T20:46:52.308Z [ERROR] agent.auth.handler: error authenticating: ... backoff=820ms
2026-04-15T20:46:57.850Z [ERROR] agent.auth.handler: error authenticating: ... backoff=1.5s
2026-04-15T20:47:06.425Z [ERROR] agent.auth.handler: error authenticating: ... backoff=2.54s
2026-04-15T20:47:14.803Z [ERROR] agent.auth.handler: error authenticating: ... backoff=4.34s
```

Important: old pods were NOT deleted because the new pod never became Ready.
Rolling update strategy kept old pods serving traffic — service stayed available.

# DNS resolution chain

```
Pod (vault-agent-init)
  └─► DNS query for vault.lab.local
        └─► CoreDNS (10.96.0.10)
              └─► Forwards to FreeIPA DNS (10.0.60.10)
                    └─► FreeIPA DOWN → "server misbehaving"
```

`10.96.0.10` = CoreDNS service IP. CoreDNS forwards `.lab.local` queries to
FreeIPA. FreeIPA down = DNS resolution fails.

# Recovery after IPA restore

```
ssh root@freeipa 'ipactl start'
```

The stuck pod recovered immediately:
```
wordpress-7b8c7d879-xbzfr    0/2     Init:1/2          0             29m
wordpress-7b8c7d879-xbzfr    0/2     PodInitializing   0             29m   ← IPA restored
wordpress-7b8c7d879-xbzfr    2/2     Running           0             29m   ← SUCCESS
wordpress-56bf4b697d-8k8jc   2/2     Terminating       1 (61m ago)   89m   ← Old pod cleanup
```

Final state — all new pods running:
```
NAME                        READY   STATUS    RESTARTS   AGE
wordpress-7b8c7d879-27b9j   2/2     Running   0          3m37s
wordpress-7b8c7d879-7tzht   2/2     Running   0          3m24s
wordpress-7b8c7d879-xbzfr   2/2     Running   0          33m
```

_____________________________________________________________________

[Final Root Cause]
Vault Agent uses hostname `vault.lab.local` for the Vault server address.
Pod-level DNS resolution goes through CoreDNS, which forwards `.lab.local`
queries to FreeIPA DNS. When FreeIPA is down:

1. Running vault-agent sidecars eventually crash after ~10 minutes of retries
   (but app containers continue running with cached credentials)
2. New vault-agent-init containers can't complete initial authentication,
   blocking pod startup indefinitely

Critical implication: node failure during IPA outage = pods can't reschedule
to other nodes.

_____________________________________________________________________

[Final Solution]

# Investigation sequence

First wrong assumption: I thought `/etc/hosts` on K8s nodes would help — added
`vault.lab.local` entry. But pods don't use the node's `/etc/hosts`. CoreDNS
handles pod DNS, and CoreDNS only forwards to `/etc/resolv.conf`, not `/etc/hosts`.

Key realization:
```
vault.lab.local = internal domain (.lab.local)
8.8.8.8 = external DNS (Google)
8.8.8.8 doesn't know about .lab.local — it's internal!
```

When FreeIPA is down, external DNS fallback doesn't help for internal domains.
Only FreeIPA knows `.lab.local` records. The fix needs to be in CoreDNS itself.

# Fix: CoreDNS hosts plugin

Added `hosts` block to CoreDNS ConfigMap BEFORE the `forward` line:

```
kubectl edit configmap coredns -n kube-system
```

```
        prometheus :9153
        hosts {
            10.0.62.100 vault.lab.local vault
            10.0.61.100 k8s.lab.local k8s
            fallthrough
        }
        forward . /etc/resolv.conf {
           max_concurrent 1000
        }
```

CoreDNS `hosts` plugin is checked BEFORE `forward` — static entries resolve
immediately without contacting any upstream DNS server.

Restarted CoreDNS:
```
kubectl rollout restart deployment coredns -n kube-system
```

# Verification

DNS resolution from test pod:
```
kubectl run test-dns --rm -it --image=busybox -- nslookup vault.lab.local
Server:        10.96.0.10
Address:    10.96.0.10:53

Name:    vault.lab.local
Address: 10.0.62.100
```

WordPress pods with vault-agent:
```
kubectl get pods -n apps
NAME                         READY   STATUS    RESTARTS   AGE
wordpress-6bf87d667d-bkjx2   2/2     Running   0          53s
wordpress-6bf87d667d-h77vz   2/2     Running   0          42s
wordpress-6bf87d667d-zzq9l   2/2     Running   0          15m
```

All pods Running 2/2 — vault-agent-init completed successfully.

# Permanent fix (Flux GitOps)

Created Flux-managed CoreDNS config to persist across cluster rebuilds:

```
kubernetes/dev/deployments/infrastructure/coredns/
├── kustomization.yaml
└── coredns-custom.yaml
```

Updated `kubernetes/dev/deployments/infrastructure/kustomization.yaml`:
```yaml
resources:
  - namespaces
  - priority-classes
  - storage
  - vault
  - ingress
  - coredns    # ← Added
```

Verified: Yes — CoreDNS resolves vault.lab.local via hosts plugin regardless of
FreeIPA status. New pods start successfully even during IPA outage.

_____________________________________________________________________

[Risk Level] MEDIUM

Existing pods survive IPA outage (vault-agent crashes but app containers keep
running with cached credentials). New pod scheduling is blocked until fix is
applied. Node failure during IPA outage is the critical risk — pods can't
reschedule.

_____________________________________________________________________

[References]
- disaster-recovery/network-ipa-dns-outage.md — DR test: IPA down DNS cascade
- TS-K8S-034 — WordPress external DNS slowness (related, same DR test)
- troubleshooting/linux/3-linux-nodes-dns-fallback.md — TS-LNX-003: Linux node DNS fallback
- kubernetes/dev/deployments/infrastructure/coredns/ — Flux-managed CoreDNS config
