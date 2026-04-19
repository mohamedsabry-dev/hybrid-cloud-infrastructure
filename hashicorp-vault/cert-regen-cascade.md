# The IPA cert / VIP SAN / `managedby` cascade

The regeneration of Vault's TLS certs to cover the `vault.lab.local` VIP name is one of those operations that looks like a 3-line change on paper (add a SAN, re-enroll, restart) and in practice touches four separate layers of the platform (FreeIPA host objects, FreeIPA service objects, Certmonger on the Vault nodes, and the Vault Agent sidecars inside Kubernetes). This file captures the cascade — what has to happen in what order, why each step exists, and the specific traps (`[TS-VLT-002]`) that ate an afternoon the first time I went through it. The high-level context is in [`DESIGN.md`](DESIGN.md) "third shift"; this file is the operational detail.

---

## Why this exists as its own doc

Most cert-related concerns in the repo are one-liners: "the cert renews via Certmonger, no manual work needed." That's true **for the normal renewal case** — Certmonger polls FreeIPA, gets a new cert, Vault reloads, done. But the case where you're **changing what the cert covers** (adding a SAN, adding a hostname, migrating from per-node certs to a shared VIP cert) is structurally different. You're not renewing an existing cert; you're asking FreeIPA to issue a different cert, which requires different permissions than renewing.

The cascade shows up any time the cert's *identity* changes. That's rarer than renewal, but the repo is going to see it again: when I migrate to different VIPs, when I add another service in front of Vault, when I rotate keys and want to change the cert principal, or when FreeIPA itself gets upgraded and the managedby semantics shift. Writing this down means next time doesn't cost another afternoon.

---

## The setup — what we're trying to achieve

Before this work, each Vault node had a FreeIPA-issued cert covering only its own hostname:

- `vault1.lab.local` → cert with CN=`vault1.lab.local`, SAN=`vault1.lab.local`
- `vault2.lab.local` → cert with CN=`vault2.lab.local`, SAN=`vault2.lab.local`
- `vault3.lab.local` → cert with CN=`vault3.lab.local`, SAN=`vault3.lab.local`

Clients that connected to a node directly got a cert matching that node's hostname, TLS was happy.

Then the VIP (`vault.lab.local` → `10.0.52.100` dev / `10.0.62.100` prod) landed in front of the cluster. Now the injector (and every client) is configured to talk to `https://vault.lab.local:8200`. When the request arrives at whichever Vault node currently holds the VIP, that node presents *its own* cert (`vault1.lab.local` or whichever). The client sees: "I asked for vault.lab.local, I got back a cert for vault1.lab.local" → **TLS name verification fails** → connection rejected.

The fix is conceptually simple: each node's cert needs to cover BOTH its own hostname AND `vault.lab.local` as SANs. That way whichever node is currently holding the VIP presents a cert valid for both names, and clients talking to `vault.lab.local` see a valid match.

Implementing "each node's cert covers both names" is where the cascade lives.

---

## The four layers involved

Any cert SAN change in this setup touches:

```
Layer 1: FreeIPA host objects
         - vault1.lab.local (real host)
         - vault2.lab.local (real host)
         - vault3.lab.local (real host)
         - vault.lab.local  (VIP — added as a host-without-keytab)

Layer 2: FreeIPA service principals
         - HTTP/vault1.lab.local@LAB.LOCAL
         - HTTP/vault2.lab.local@LAB.LOCAL
         - HTTP/vault3.lab.local@LAB.LOCAL
         (no service principal for vault.lab.local — the VIP isn't a standalone service)

Layer 3: managedby permissions between Layer 1 and Layer 2
         - Each vaultN service must be "managedby" the vaultN host (own hostname)
         - Each vaultN service must ALSO be "managedby" the vault.lab.local host (the VIP)
         (This is the trap. The second managedby is what took me an afternoon to find.)

Layer 4: Certmonger on each Vault node
         - Watches for cert expiry / SAN mismatches
         - Talks to FreeIPA to request new certs
         - Writes renewed certs to /etc/pki/vault/ (or equivalent)
         - Triggers post-renewal hook: SIGHUP or systemctl reload to make Vault re-read the cert
```

And then **inside Kubernetes**, the Vault Agent sidecars also care about this — but only indirectly via the `vault-ca` Secret in each app namespace (that's the IPA CA cert, not the Vault node cert). The injector sidecars trust anything signed by the IPA CA, so once the node certs are valid, the sidecars work. The CA itself doesn't change during this operation.

---

## The cascade, step by step

This is the actual order that works. When I first did this, I did several of these steps out of order and each permutation failed with a different error. The order is load-bearing.

### Step 1 — Add `vault.lab.local` as a host object in FreeIPA

```bash
ssh super_bot@<ipa-server>
kinit admin
ipa host-add vault.lab.local --force    # --force because there's no A record yet for it
```

Why: FreeIPA's cert-issuance logic requires every hostname that appears in a cert's SAN to exist as a host object. Even if that hostname is a VIP and doesn't have a keytab / real machine behind it. The `--force` is because normally `ipa host-add` wants to resolve the hostname before adding; for a VIP that resolves to the right IP (10.0.52.100) but isn't a "real" machine, `--force` bypasses the sanity check.

Then add the DNS entry so the VIP hostname actually resolves:

```bash
ipa dnsrecord-add lab.local vault --a-rec 10.0.52.100    # or 10.0.62.100 for prod
```

This is also in [`../ansible/dev/playbooks/freeipa/add_dns_records.yml`](../ansible/dev/playbooks/freeipa/add_dns_records.yml) as an idempotent Ansible task — I ran it manually the first time, then added it to the playbook.

### Step 2 — Grant each `vaultN` service `managedby` on the new `vault.lab.local` host object

**This is the trap.** There are two CLI verbs that look like they do the same thing, and one is wrong:

```bash
ipa service-add-managedby HTTP/vault1.lab.local@LAB.LOCAL --hosts=vault.lab.local
# NO — this does NOT do what you want.
```

```bash
ipa service-mod HTTP/vault1.lab.local@LAB.LOCAL --addattr=managedby='fqdn=vault.lab.local,cn=computers,cn=accounts,dc=lab,dc=local'
# YES — this is the one that actually sets the managedby attribute for cert issuance.
```

What's the difference? `service-add-managedby` in the IPA CLI manages a different LDAP attribute than the one the cert issuance code actually checks. It grants a host the "ability to manage" a service in the sense of administrative control, not the "ability to request certs referencing this host's name as a SAN." The cert-issuance code specifically checks the `managedby` attribute on the service object, and `service-add-managedby` updates a different attribute.

I found this out by tracing the failed cert request through FreeIPA's ACL logs, finding the LDAP search query, and comparing the attribute it was checking against what `ipa service-show` was returning. The logs said "no matches" for a permission that, from the CLI, appeared to be granted. Two different LDAP attributes with similar-sounding semantics.

The correct command pattern (from `[TS-VLT-002]` — full writeup at [`../troubleshooting/vault/2-freeipa-vip-certificate-san-managedby.md`](../troubleshooting/vault/2-freeipa-vip-certificate-san-managedby.md)):

```bash
ipa service-mod HTTP/vault1.lab.local@LAB.LOCAL \
  --addattr=managedby='fqdn=vault.lab.local,cn=computers,cn=accounts,dc=lab,dc=local'

ipa service-mod HTTP/vault2.lab.local@LAB.LOCAL \
  --addattr=managedby='fqdn=vault.lab.local,cn=computers,cn=accounts,dc=lab,dc=local'

ipa service-mod HTTP/vault3.lab.local@LAB.LOCAL \
  --addattr=managedby='fqdn=vault.lab.local,cn=computers,cn=accounts,dc=lab,dc=local'
```

After this, each vault service principal is "managed by" both its own host AND the new VIP host. That's what the cert-issuance code needs.

This step is also captured in [`../ansible/dev/playbooks/vault/crt-change.txt`](../ansible/dev/playbooks/vault/crt-change.txt) which is my running note log of cert-related operations.

### Step 3 — Request the new cert with the VIP SAN via Certmonger

On each Vault node, tell Certmonger to request a cert that includes both the node's hostname and the VIP:

```bash
ssh super_bot@vault1
sudo ipa-getcert request \
  -K HTTP/vault1.lab.local \
  -k /etc/pki/vault/key.pem \
  -f /etc/pki/vault/cert.pem \
  -N "CN=vault1.lab.local" \
  -D vault1.lab.local \
  -D vault.lab.local \
  -C "systemctl reload vault"    # post-save hook to reload Vault
```

The key flags:
- `-K HTTP/vault1.lab.local` → the service principal for this node
- `-D vault1.lab.local -D vault.lab.local` → **two `-D` flags**, one per SAN. The first is the node's own hostname, the second is the VIP.
- `-C "systemctl reload vault"` → Certmonger runs this after writing the new cert, telling Vault to pick it up without a full restart

Repeat on vault2 and vault3 with their respective hostnames.

### Step 4 — Verify the new cert's SAN list

```bash
openssl x509 -in /etc/pki/vault/cert.pem -text -noout | grep -A 3 "Subject Alternative Name"
```

Expected output:

```
X509v3 Subject Alternative Name:
    DNS:vault1.lab.local, DNS:vault.lab.local
```

If only `vault1.lab.local` shows up, Certmonger got a cert issued by IPA with only the first SAN — which is the symptom that the `managedby` from step 2 wasn't set correctly. Go back and verify the LDAP attribute. If the cert shows both SANs, the chain is working.

### Step 5 — Reload Vault (should already be done by the `-C` hook)

```bash
sudo systemctl reload vault
# Or:
# sudo systemctl restart vault    # if reload is not respected
```

A full restart triggers the unseal flow (KMS) again; reload is preferred when supported. Verify Vault is still responding:

```bash
vault status   # should show Initialized: true, Sealed: false, HA mode: active (or standby)
```

### Step 6 — Verify from a client

From anywhere in the lab (my Mac Mini, a k8s pod, another Vault node):

```bash
# TLS handshake against the VIP:
openssl s_client -connect vault.lab.local:8200 -servername vault.lab.local </dev/null 2>/dev/null | openssl x509 -noout -text | grep -A 3 "Subject Alternative Name"
```

Should show the same two SANs as step 4. If it does, TLS name verification will pass for `vault.lab.local`.

### Step 7 — Check Kubernetes side

In the cluster, confirm the Vault Agent sidecars on existing pods can still auth (their cached tokens should still be valid). For new pods:

```bash
kubectl get pods -A -o wide | grep -E "Init|ContainerCreating"
```

Any pod stuck in Init is a candidate for the `vault-agent-init` container failing on TLS. Check:

```bash
kubectl logs <pod-name> -c vault-agent-init
```

If you see `x509: certificate is valid for vault1.lab.local, not vault.lab.local` — the pod is hitting a node whose cert hasn't been regenerated yet (step 3 missed on one node). Fix that node.

---

## The service-account dependency problem

Step 3 above has a side-effect that caused follow-on breakage the first time: **when Certmonger requests a new cert, it uses the node's IPA host keytab to authenticate**. The host keytab has to be valid. If a Vault node's IPA enrollment is broken (keytab expired, time skew, missing principal), Certmonger's cert request fails with a Kerberos error, not a cert error — which is a confusing symptom to debug when you're looking for "why is my new cert not issuing."

The dependency chain:

```
Certmonger request
  ↓
Kerberos GSSAPI auth (uses /etc/krb5.keytab)
  ↓ (if keytab is valid)
IPA CLI call (`ipa cert-request`)
  ↓ (if IPA ACLs allow via managedby)
Dogtag CA signs new cert
  ↓
Certmonger writes cert + key to disk
  ↓
`-C` post-save hook runs (systemctl reload vault)
```

Any broken link in that chain = new cert doesn't happen. Symptoms I hit:

- **Kerberos clock skew** — the Vault LXC container's clock drifted, Kerberos rejected the auth with "clock skew too great." Fixed by running NTP inside the LXC and verifying with `chronyc sources`. Now part of the Ansible pre_setup that every Vault node runs before vault_setup.
- **Missing `managedby` after an IPA upgrade** — after FreeIPA was updated, the `managedby` attributes I'd set with `ipa service-mod` had been normalized to a different form. Re-running the `service-mod` commands from step 2 fixed it, but I had to notice first.
- **Vault node's IPA host object got orphaned** — an LXC rebuild with the same hostname created a duplicate IPA host with a different SID, the old managedby references pointed at the orphaned host, cert requests failed with "principal not found." Cleaned up via `ipa host-del` on the orphan, re-enrolled, re-granted managedby.

None of these are specifically Vault's fault. They're FreeIPA-operational concerns that Vault's cert story happens to expose.

## The update-sequence problem

The other side-effect: **when multiple Vault nodes need to regenerate certs concurrently, they can't all do it at once** — because while a node is in the cert-regen flow, it's briefly reloading Vault, and if the current VIP holder reloads during the wrong moment, the VIP can fail over to a node that's *also* mid-reload, causing both to flap.

The correct sequence is: regenerate cert on vault3 first (a follower), then vault2 (another follower), then vault1 (the leader, who holds the VIP). Each node finishes its reload and returns to a stable state before the next one starts.

Automation-wise: the `vault_setup.yml` Ansible playbook used to run this as a `serial: 1` loop (one node at a time) but I've seen it run parallel when someone (me) edited a local copy and ran it without the serial flag. The fix is the playbook enforces `serial: 1` for the cert-regen task specifically; non-cert tasks can run in parallel.

Documented in-place in the playbook. Worth knowing for anyone who takes over — don't run the vault cert regen in parallel across nodes.

---

## What this cascade costs if you get it wrong

Since the cascade involves TLS, every failure mode takes the form of "clients can't talk to Vault." The blast radius depends on where in the chain it breaks:

| Failure point | Blast radius |
|---------------|-------------|
| Step 1 (host object missing) | Cert request fails immediately; no new cert issued; old cert still valid until expiry. Low immediate impact. |
| Step 2 (`managedby` wrong verb) | Same — cert request fails, old cert still valid. |
| Step 3 (Certmonger can't request) | Same — old cert still valid. |
| **Step 3-6 mid-flight, partial cert on some nodes** | **This is the bad case.** Some nodes present the new (correct) cert, some present the old (wrong) cert. Clients hitting the VIP see inconsistent TLS behavior — works sometimes, fails other times depending on which node holds the VIP. Debugging hell. |
| Step 5 (Vault doesn't reload) | Vault is still using the old cert — clients fail the same as before. Manual restart fixes it. |
| Step 7 (sidecars in k8s) | Existing sidecars have cached tokens, keep working. New pods fail to start. Slow-burn outage across the cluster as pods restart organically. |

The mid-flight inconsistency is the case to be careful of — which is why the serial sequence matters.

## Related files

- **TS case:** [`../troubleshooting/vault/2-freeipa-vip-certificate-san-managedby.md`](../troubleshooting/vault/2-freeipa-vip-certificate-san-managedby.md) — the full writeup of the `service-mod` vs `service-add-managedby` trap
- **TS case cross-ref:** [`../troubleshooting/vault/1-vault-cluster-initial-setup-investigation.md`](../troubleshooting/vault/1-vault-cluster-initial-setup-investigation.md) — the broader cert-setup issues from the initial Vault deployment (GPG signatures, Certmonger `--force`, CSR hostname mismatch, cert permissions)
- **Ansible running notes:** [`../ansible/dev/playbooks/vault/crt-change.txt`](../ansible/dev/playbooks/vault/crt-change.txt) / [`../ansible/prod/playbooks/vault/crt-change.txt`](../ansible/prod/playbooks/vault/crt-change.txt) — my chronological notes on cert changes for dev and prod
- **FreeIPA DNS playbook:** [`../ansible/dev/playbooks/freeipa/add_dns_records.yml`](../ansible/dev/playbooks/freeipa/add_dns_records.yml) — adds the `vault.lab.local` A record alongside others
- **Vault setup playbook:** [`../ansible/dev/playbooks/vault/vault_setup.yml`](../ansible/dev/playbooks/vault/vault_setup.yml) — the main deployment, includes the cert-request tasks (with `serial: 1` for cert-regen)
- **VIP/keepalived playbook:** [`../ansible/dev/playbooks/vault/vault_vip.yml`](../ansible/dev/playbooks/vault/vault_vip.yml) — the VIP that made this cascade necessary
- **FreeIPA-related TS:** [`../troubleshooting/identity/`](../troubleshooting/identity/) — adjacent cert-enrollment issues (Kerberos auth, LXC UID remapping, keytab preauth, sudo/SSSD)
- **DR test:** [`../disaster-recovery/ipa-domain-down-dr-test.md`](../disaster-recovery/ipa-domain-down-dr-test.md) — the "what happens when IPA is gone" test, which indirectly exercises the Vault cert dependency
- **Vault signal flow:** [`../deployment-docs/signal-flows/vault-k8s-auth-signal-flow.txt`](../deployment-docs/signal-flows/vault-k8s-auth-signal-flow.txt)
- **Vault DR test for single-node:** [`../disaster-recovery/vault-single-node-down.md`](../disaster-recovery/vault-single-node-down.md) — tests the "a node with a cert is down, VIP moves" scenario
