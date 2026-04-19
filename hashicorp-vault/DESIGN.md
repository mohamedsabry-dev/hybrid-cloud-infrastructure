# Vault — the evolution story

How Vault in this repo grew from a POC-plan clone (raft + no TLS, 3 IPs, local) into what's running today (raft + TLS via IPA, 3 nodes behind a keepalived VIP resolving to `vault.lab.local`, AWS KMS auto-unseal, Vault Agent Injector wired into every workload that holds a secret, AWS Secrets Engine minting temporary STS credentials for the etcd-backup CronJob). None of this was the original plan. Each layer was added because the layer below it forced the question, and each question had an answer that wasn't in the POC. That's the shape of the story and the reason it deserved to be written down rather than inferred from reading nine different folders.

---

## Starting point — the POC plan

The POC version (archived under [`../archive-poc-v1/automation/ansible/vault/`](../archive-poc-v1/automation/ansible/vault/)) was deliberately simple: 3 Vault nodes on a flat network, Raft storage backend, **no TLS**, **no VIP**, **no KMS auto-unseal**. Clients talked to Vault over plain HTTP against one of the 3 node IPs directly. The design rationale there was "prove the thing works in isolation, then harden later." It was correct for the POC scope. It wasn't going to survive contact with a real cluster.

When I started the current-generation repo, my plan was to clone that POC design verbatim and move on — Raft is still the right choice for a small cluster, and 3 nodes is still the right number, and no-TLS for a private lab is at least defensible. I was going to skip the hardening because the hardening was "later" and "later" hadn't arrived.

## First shift — IPA cert and HTTPS

The first thing that forced a redesign was that I already had **FreeIPA running** with its own CA. The IPA CA was sitting there, issuing certs for every other service in the lab, and if Vault was the one service speaking plain HTTP, that was a lab-internal cognitive-dissonance I didn't want to live with. So before the first deploy, the plan shifted: Vault would enroll as a FreeIPA service, each node would hold an IPA-issued TLS cert under its own hostname (`vault1.lab.local`, `vault2.lab.local`, `vault3.lab.local`), and Vault would speak HTTPS only.

Mechanics: each Vault node is an LXC container joined to the IPA realm as a host principal. The Ansible playbook at [`../ansible/dev/playbooks/vault/vault_setup.yml`](../ansible/dev/playbooks/vault/vault_setup.yml) (and prod equivalent) requests a service principal via `ipa service-add`, enrolls Certmonger to pull the cert, and points Vault's listener config at the resulting `.pem` files. Certmonger handles renewal on its own — if the IPA cert has `auto_renew` set, Certmonger will re-issue before expiry without a Vault outage, provided the service principal and managedby permissions are correct (more on this below — that "provided" carried more weight than I expected).

The `vault.hcl.j2` template that holds this listener config is [`../ansible/dev/playbooks/vault/templates/vault.hcl.j2`](../ansible/dev/playbooks/vault/templates/vault.hcl.j2) — compare it against the archive version ([`../archive-poc-v1/automation/ansible/vault/vault.hcl.j2`](../archive-poc-v1/automation/ansible/vault/vault.hcl.j2)) to see the TLS-vs-HTTP evolution side by side.

## Second shift — the VIP problem I didn't see until the k8s injector

First deploy went out with the TLS-via-IPA design and **three direct IPs** — no VIP. Vault's built-in forwarding would handle "you asked the follower, I'll forward to the leader" for clients that were sharp enough to use the full cluster list, and the manual Vault clients (`vault` CLI from the admin laptop, the ansible playbooks) were fine because they were pointed at a single node with the understanding that I'd rotate if that node went down.

The question that forced the VIP was this line in the Vault Agent Injector Helm values (look at [`../kubernetes/dev/deployments/infrastructure/vault/vault.yaml`](../kubernetes/dev/deployments/infrastructure/vault/vault.yaml)):

```yaml
values:
  global:
    externalVaultAddr: "https://vault.lab.local:8200"
```

There is **one** address there. The injector takes that address and bakes it into every `vault-agent-init` and `vault-agent` sidecar that gets injected into every pod in the cluster. If I hardcoded one of the three node IPs — say, `vault1.lab.local` — then:

- If `vault1` is the leader: every sidecar talks to the leader, everything works.
- If `vault1` is a follower: every sidecar talks to the follower, the follower forwards to the leader, everything still works (Vault does that internally — this is the "Vault does its own balancing" property, which is real and genuinely nice).
- **If `vault1` is down** and the cluster is healthy on `vault2`+`vault3`: every sidecar still tries `vault1.lab.local`, the connection fails, the sidecar retries, pods never come Ready. The two healthy Vault nodes are useless to the cluster because the cluster doesn't know they exist.

That third scenario is the one that killed the "hardcode one node" idea. A Vault that's up but unreachable from the k8s data plane is functionally no Vault at all. I needed something in front of the 3 nodes that would answer on a single address and route to whichever nodes were alive.

This is the same problem I'd already solved for the Kubernetes API server — 3 master nodes behind a **keepalived VIP** on `10.0.52.100:16443` (dev) / `10.0.62.100:16443` (prod), so that the `server:` URL in every kubeconfig is one stable endpoint. Same pattern applied to Vault:

- A new VIP, `10.0.52.100:8200` (dev) / `10.0.62.100:8200` (prod)
- Keepalived running on all 3 Vault nodes, one holds the VIP at a time
- FreeIPA DNS entry: `vault.lab.local` → the VIP
- Every client (injector, CLI, playbook) talks to `vault.lab.local`, which is always answered by whichever Vault node is alive and holding the VIP

The keepalived config lives in [`../ansible/dev/playbooks/vault/vault_vip.yml`](../ansible/dev/playbooks/vault/vault_vip.yml) (the playbook that configures it) and [`../ansible/dev/playbooks/vault/templates/vault-keepalived.conf.j2`](../ansible/dev/playbooks/vault/templates/vault-keepalived.conf.j2) (the template).

### Why no HAProxy / nginx in front

The usual "3 nodes behind a VIP" pattern includes a layer-7 load balancer in front — HAProxy, nginx, or equivalent — doing health checks, session pinning, TLS termination, request routing. I deliberately did not add one.

Reason: **Vault does internal request forwarding by design.** If a follower receives a write request, it forwards it to the leader transparently and returns the leader's response to the client. Reads can be served from any node (follower or leader, depending on consistency mode). The only thing a layer-7 LB would have added is:

1. Leader-awareness routing (send writes directly to leader, skip the forwarding hop) — *micro-optimization, not worth a new moving part*
2. Health-check based member removal (don't send traffic to a dead node) — *keepalived already does this at layer-3; the VIP only moves to a node that's running keepalived+Vault*
3. TLS termination — *I want end-to-end TLS to Vault, not termination at the LB, so this is the opposite of what I need*

So the stack is: `client → VIP (keepalived, layer-3) → active Vault node (holds VIP) → Vault's own forwarding (if follower) → leader`. No HAProxy layer. One less thing to fail, one less thing to certificate. This is one of the very few places in the platform where I got to remove an obvious-seeming component because the system beneath it was smarter than the usual "apps need a load balancer" assumption. Vault is not a stateless HTTP service; it's a consensus system that already knows where its leader is.

## Third shift — the IPA cert didn't trust the VIP

The VIP plan is conceptually clean. The implementation had one trap waiting. The IPA-issued certs for `vault1/2/3.lab.local` covered **each node's own hostname**, not the new VIP hostname `vault.lab.local`. When a client (the injector sidecar, the `vault` CLI, anything) connected to `https://vault.lab.local:8200` and got a cert back whose CN/SAN said `vault1.lab.local`, TLS rejected it as a name mismatch.

The fix is conceptually trivial: add `vault.lab.local` as a **Subject Alternative Name (SAN)** to each node's cert, so a cert presented by any of the 3 nodes covers both its own hostname and the shared VIP name. IPA supports this through the service principal's SAN list.

The fix in practice required figuring out three things I didn't know going in:

1. **IPA requires the VIP to exist as a host object** before it will issue a cert that references it. So `ipa host-add vault.lab.local` first (even though `vault.lab.local` is a VIP, not a real host with a keytab).

2. **The SAN on the service cert needs `managedby` permissions set correctly** — not on the service object alone, but on **both** the service and the host that's listed in the SAN. This is the trap behind `[TS-VLT-002]` (the VIP cert SAN + managedby incident). See the full write-up in [`cert-regen-cascade.md`](cert-regen-cascade.md) and the TS file at [`../troubleshooting/vault/2-freeipa-vip-certificate-san-managedby.md`](../troubleshooting/vault/2-freeipa-vip-certificate-san-managedby.md).

3. **The correct CLI to grant that `managedby` is `ipa service-mod` with the right flag — NOT `ipa service-add-managedby`**, which does something subtly different and doesn't actually grant the permission the Certmonger cert request needs. I lost an afternoon on that one.

Once those three things were right, Certmonger re-enrolled the cert with the VIP SAN, each Vault node now presented a cert valid for both its own hostname and `vault.lab.local`, and clients talking to the VIP stopped getting TLS rejections. That's the cert regen cascade in abbreviated form; the long version with the exact commands is [`cert-regen-cascade.md`](cert-regen-cascade.md).

### Why I kept this cascade alive as a documented concern

Because it's going to happen again. Every time the IPA cert expires, Certmonger re-enrolls — and if I ever change anything about the SAN list, the hostnames, the FreeIPA service principals, or the managedby chain, I'm back in exactly this situation. The cascade's lesson isn't "here's how to fix it one time," it's "here's the multi-step re-enrollment workflow that has to stay intact for the VIP cert to keep working across rotations." The service account dependencies, the playbook update sequence, and the Vault-side cert reload are all parts of that workflow and they all have to be consistent.

## Fourth shift — the Kubernetes injector pattern

With TLS working and the VIP answering, the Kubernetes integration came next. This is where the pattern gets consolidated — what I first did by hand for the first app, I turned into a helper script after the third app, and applied to every subsequent app without variation.

The baseline pattern is:

1. Each app has a **ServiceAccount** in its namespace — not the namespace's default SA.
2. That SA has a **long-lived token Secret** (K8s 1.24+ requires this explicit Secret — the same pattern as [`../kubernetes/dev/deployments/infrastructure/vault/vault-auth-sa.yaml`](../kubernetes/dev/deployments/infrastructure/vault/vault-auth-sa.yaml)).
3. On the **Vault side**, a policy is written granting read on the app's secret paths (e.g., `secret/data/wordpress/*`), and a Kubernetes auth role binds that policy to `{namespace: <app-namespace>, service_account_name: <sa-name>}`.
4. The app's **Deployment / StatefulSet** carries a set of annotations:
   - `vault.hashicorp.com/agent-inject: "true"`
   - `vault.hashicorp.com/role: <app-role>`
   - `vault.hashicorp.com/agent-inject-secret-<name>: secret/data/<path>`
   - `vault.hashicorp.com/agent-inject-template-<name>: <go-template rendering the secret>`
   - `vault.hashicorp.com/tls-secret: vault-ca` (to trust the IPA CA when talking to `vault.lab.local`)
5. A **`vault-ca-secret.yaml`** in the app's manifest folder carries the IPA CA cert so the sidecar trusts TLS.

Every app that holds a secret goes through this pattern. WordPress, MariaDB, Grafana (via kube-prometheus-stack), the remediation controller, the etcd-backup CronJob, the nginx test app. Same annotations, same SA + token + policy + role structure. The only thing that varies is the secret paths and the role name.

After doing this by hand for the first two apps and making the same class of mistake both times (forgetting to bind the correct SA, or setting up a policy but not the role, or not mounting the CA secret), I wrote the helper: [`../kubernetes/docs/vault-pod-setup.sh`](../kubernetes/docs/vault-pod-setup.sh). It prompts for the app name, namespace, SA, and secret path; creates the Vault policy; creates the Kubernetes auth role; and stores any initial secrets in Vault at the right path. **One interactive run per new app, and the Vault side is ready.** The app-side annotations are added to the manifest separately (those still need a manual copy-paste into the Deployment/StatefulSet yaml), but the Vault-side setup is now idempotent and fast.

The injection pattern details, TS cases, and the full annotation template are in [`k8s-integration.md`](k8s-integration.md).

## Fifth shift — AWS KMS auto-unseal

Every time Vault restarts, it comes up sealed. Sealed Vault is useless — it can't answer any auth or secret requests until someone provides enough unseal keys to cross the threshold (default: 3 of 5 Shamir shares). In a lab with 3 nodes and frequent restarts (for patching, config changes, VIP drills), the "SSH in and paste unseal keys three times after every restart" loop is intolerable.

The POC didn't solve this; I was going to solve it "later." Later arrived when I added AWS to the project. Once the AWS bootstrap was in place (see [`../aws/DESIGN.md`](../aws/DESIGN.md)), KMS became the obvious answer:

- Create a dedicated KMS key with alias `alias/vault-unseal` in each env's AWS account
- Create a dedicated IAM user `vault_unseal` whose policy grants only `kms:Encrypt` / `kms:Decrypt` / `kms:DescribeKey` against that specific key
- Vault's `seal "awskms"` stanza in `vault.hcl` references the key by alias, and uses `vault_unseal`'s access keys via a systemd EnvironmentFile (`/etc/vault.d/vault.env`)
- On startup, Vault asks KMS to decrypt its internal unseal key; if KMS approves, Vault unseals automatically. No human in the loop.

Terraform provisions the KMS key + user + Secrets Manager entries holding the access keys: [`../terraform/dev/aws/kms-vault-unseal/`](../terraform/dev/aws/kms-vault-unseal/) (dev) / [`../terraform/prod/aws/kms-vault-unseal/`](../terraform/prod/aws/kms-vault-unseal/) (prod).

GitHub Actions workflow [`prod-aws-kms-vault-unseal.yml`](../.github/workflows/prod-aws-kms-vault-unseal.yml) (and dev equivalent) applies the Terraform. A separate concern — the credential injection into the Vault systemd env file — goes through the Ansible vault_setup playbook, which pulls the keys from AWS Secrets Manager at runtime and templates them into [`../ansible/dev/playbooks/vault/templates/vault.env.j2`](../ansible/dev/playbooks/vault/templates/vault.env.j2). That injection path is where `[TS-VLT-003]` happened: a manual playbook run that bypassed the GitHub Actions secret-fetch step resulted in empty AWS credentials in `vault.env`, and Vault refused to start. The fix was a `when:` gate in the playbook that now asserts the credential length before templating — no more silent empty strings. See [`kms-unseal.md`](kms-unseal.md) for the full story.

Recovery keys from `vault operator init` are stored in AWS Secrets Manager under `<env>/vault/unseal-keys` — those are the **master unseal keys**, separate from the KMS credentials. KMS can unseal Vault automatically, but recovery from a catastrophic state still requires those master keys. They're held in AWS so I can't lose them through a local-storage mishap, and they're protected by AWS IAM rather than my laptop's filesystem.

This is the "dependency on AWS" tradeoff, spelled out deliberately: **Vault unseal now depends on AWS KMS being reachable**. If AWS is down (unlikely for eu-west-2 / us-east-1 simultaneously, but possible for network-side reachability from my lab), Vault cannot auto-unseal after a restart, and I fall back to manually providing the master keys from AWS Secrets Manager (which I can retrieve via the AWS console from any machine with IAM access). The DR test for this scenario is [`../disaster-recovery/vault-aws-kms-dependency.md`](../disaster-recovery/vault-aws-kms-dependency.md) — it confirms the fallback works and documents the exact manual-unseal procedure.

## Sixth shift — the AWS Secrets Engine for etcd backup

The last layer is the one I was most unsure about when I built it, and the one that has the least dedicated documentation anywhere else in the repo. That's why it gets its own sub-story: [`etcd-backup-role.md`](etcd-backup-role.md).

The problem: the etcd-backup CronJob needs to upload etcd snapshots to S3. That means it needs AWS credentials. The naive approach is "put long-lived AWS credentials in a Kubernetes secret and mount them." That's the wrong pattern — long-lived AWS keys in a k8s secret is the exact thing Vault is supposed to replace.

The right pattern is: **Vault mints short-lived STS credentials** on demand, backed by an AWS IAM role the `vault_trust` user can assume. The etcd-backup pod asks Vault for credentials via a Vault Agent sidecar, gets temporary access/secret/session keys scoped to the `etcd-backup` IAM role (which has exactly `s3:PutObject` on the backup bucket), uses them to upload the snapshot, and the credentials expire within an hour. No long-lived keys anywhere in k8s.

The pieces:

- `vault_trust` IAM user created by [`../terraform/dev/aws/vault-trust/iam.tf`](../terraform/dev/aws/vault-trust/iam.tf), permitted to `sts:AssumeRole` against the `etcd-backup` role
- `etcd-backup` IAM role with a trust policy allowing `vault_trust` to assume it, and an S3 access policy scoped to the backup bucket
- Vault's AWS Secrets Engine enabled and configured (by the Ansible playbook [`../ansible/dev/playbooks/vault/vault-trust-aws.yml`](../ansible/dev/playbooks/vault/vault-trust-aws.yml)) with `vault_trust`'s keys, so Vault knows how to call STS on its behalf
- A Vault role named `etcd-backup` configured to return credentials for the `etcd-backup` IAM role on request, bound to the `etcd-backup-sa` service account in the `kube-system` namespace
- The etcd-backup CronJob at [`../kubernetes/dev/deployments/apps/etcd-backup/cronjob.yaml`](../kubernetes/dev/deployments/apps/etcd-backup/cronjob.yaml) carries annotations that inject temp AWS keys via a pre-upload `init` sidecar

I didn't write this up anywhere else. I was going to "after review." This hub is where that write-up lands. See [`etcd-backup-role.md`](etcd-backup-role.md).

---

## What this evolution looks like in one picture

```
POC version (archive):     3 nodes ─ raft ─ plain HTTP ─ manual unseal ─ no k8s integration
                              │
                              │ "I already have FreeIPA with a CA, why am I running HTTP?"
                              ▼
First deploy:              3 nodes ─ raft ─ TLS via IPA ─ 3 direct IPs ─ manual unseal ─ no k8s yet
                              │
                              │ "externalVaultAddr wants ONE address; hardcoding one node means
                              │  cluster is useless if that node is down"
                              ▼
VIP added:                 3 nodes ─ raft ─ TLS via IPA ─ keepalived VIP (vault.lab.local) ─ manual unseal
                              │
                              │ "IPA cert CN is nodeN.lab.local, doesn't cover vault.lab.local —
                              │  TLS name mismatch; need SAN regeneration with managedby chain"
                              ▼
Cert regen:                SAN added to service certs via ipa service-mod (NOT service-add-managedby);
                           Certmonger re-enrolls on each node; managedby must be set on both host
                           and service objects. TS-VLT-002 captures the trap.
                              │
                              │ "k8s injector now has a stable Vault endpoint — time to wire
                              │  every app to it, with consistent SA+policy+role+CA+annotations"
                              ▼
Injector pattern:          vault-pod-setup.sh helper, applied per app. Wordpress, MariaDB, Grafana,
                           remediation, etcd-backup, nginx-test. Same pattern each time.
                              │
                              │ "Manual unseal after every restart is intolerable. I now have AWS."
                              ▼
AWS KMS unseal:            KMS key alias/vault-unseal, IAM user vault_unseal, credentials in AWS SM,
                           injected into Vault systemd env via Ansible. TS-VLT-003: empty-cred incident
                           (manual run bypassed secret fetch) → added `when:` gate in playbook.
                              │
                              │ "etcd backup needs AWS creds but I refuse to put long-lived keys in k8s"
                              ▼
AWS Secrets Engine:        vault_trust IAM user, etcd-backup role, Vault mints STS creds on demand
                           for the etcd-backup CronJob. Zero long-lived AWS keys in k8s.
                              │
                              ▼
                          CURRENT STATE (2026-04-19)
```

Each step was forced by the step above it, and each answer came from what was already present in the platform (FreeIPA for certs, k8s control plane for the VIP pattern, AWS for KMS and STS). Nothing in this design is an abstract "best practice" — it's just what the previous layer left unsolved.

## What's deliberately not in scope

- **Multi-region Vault replication.** Vault Enterprise has performance-replication and DR-replication. I'm running Vault OSS. Multi-region = dev and prod are separate Vault clusters with no replication between them; I don't need a single global Vault.
- **Vault namespaces.** Enterprise feature. I use plain policies + roles scoped by Kubernetes auth namespaces instead.
- **Secret rotation automation.** Today I rotate static secrets manually (e.g., MariaDB passwords) by overwriting the Vault KV entry; the injector pattern means apps pick up the new value on next pod restart. Automated rotation with per-app rotation schedulers would be a nice-to-have but is out of scope for this phase.
- **Database dynamic secrets.** Vault can generate per-connection database creds on demand; I chose the static-KV approach for MariaDB because dynamic creds would have required connection-pooling changes in every app. Tradeoff: simpler apps, more careful manual rotation.

## Related files (per-sub-story)

- [`kms-unseal.md`](kms-unseal.md) — deep dive on AWS KMS auto-unseal, credentials flow, TS-VLT-003
- [`k8s-integration.md`](k8s-integration.md) — injection pattern, vault-pod-setup.sh, per-app annotation template, TS cases 4, 14, 17, 33
- [`etcd-backup-role.md`](etcd-backup-role.md) — AWS Secrets Engine + assume-role chain for the etcd-backup CronJob
- [`cert-regen-cascade.md`](cert-regen-cascade.md) — the IPA SAN + managedby + SA dependency cascade (TS-VLT-002)
- [`layer-map.md`](layer-map.md) — navigation index to every Vault-related file in the repo
