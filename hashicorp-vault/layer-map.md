# Vault layer map — where every piece of the implementation actually lives

The navigation index for the Vault system. Every concern — install, unseal, trust, inject, automate, troubleshoot, DR-test — maps here to the real path in the repo where the implementation actually lives. This is the file to grep when you want to find the code behind the story.

Files referenced here are **not moved** into this hub — they stay in their natural functional layer (`ansible/`, `terraform/`, `kubernetes/`, `.github/`, etc.). This map is the pointer. Whenever a file in one of those layers changes meaningfully (new app wired to Vault, new Ansible playbook, new TS case), this map should be updated so it stays the truth.

Last verified: 2026-04-19.

---

## Quick navigation by concern

| I want to... | Go to |
|--------------|-------|
| Understand the overall Vault architecture | [`DESIGN.md`](DESIGN.md) |
| Set up a new app with Vault injection | [`k8s-integration.md`](k8s-integration.md) + [`../kubernetes/docs/vault-pod-setup.sh`](../kubernetes/docs/vault-pod-setup.sh) |
| Provision a new env's Vault from scratch | [`../deployment-docs/vault-initial-setup-guide.txt`](../deployment-docs/vault-initial-setup-guide.txt) (ordered walkthrough) |
| Understand auto-unseal / rotate KMS credentials | [`kms-unseal.md`](kms-unseal.md) |
| Understand etcd-backup AWS creds flow | [`etcd-backup-role.md`](etcd-backup-role.md) |
| Regenerate or troubleshoot Vault certs | [`cert-regen-cascade.md`](cert-regen-cascade.md) + [`../troubleshooting/vault/2-freeipa-vip-certificate-san-managedby.md`](../troubleshooting/vault/2-freeipa-vip-certificate-san-managedby.md) |
| Debug a Vault-related k8s pod incident | [`../troubleshooting/kubernetes/`](../troubleshooting/kubernetes/) (filter by vault in filename) |
| Debug a Vault-node incident | [`../troubleshooting/vault/`](../troubleshooting/vault/) |
| Run a DR test on Vault | [`../disaster-recovery/`](../disaster-recovery/) (vault-* files) |
| Inspect or modify the Helm chart for the injector | [`../kubernetes/dev/deployments/infrastructure/vault/vault.yaml`](../kubernetes/dev/deployments/infrastructure/vault/vault.yaml) / [`../kubernetes/prod/deployments/infrastructure/vault/vault.yaml`](../kubernetes/prod/deployments/infrastructure/vault/vault.yaml) |
| Change the VIP address or hostname | [`../ansible/<env>/playbooks/vault/vault_vip.yml`](../ansible/dev/playbooks/vault/vault_vip.yml) + [`../ansible/<env>/playbooks/freeipa/add_dns_records.yml`](../ansible/dev/playbooks/freeipa/add_dns_records.yml) + re-run cert cascade |

---

## Layer-by-layer catalog

### Layer 1 — Ansible (install, configure, operate)

**Dev:**

| Path | Purpose |
|------|---------|
| [`../ansible/dev/playbooks/vault/vault_setup.yml`](../ansible/dev/playbooks/vault/vault_setup.yml) | Main deployment — FreeIPA service principals, Certmonger TLS enrollment, DNF install, Raft config, KMS credential injection |
| [`../ansible/dev/playbooks/vault/vault_config.yml`](../ansible/dev/playbooks/vault/vault_config.yml) | Post-init config — enables LDAP auth, creates policies (super_admin, readonly), maps FreeIPA groups, emergency userpass auth |
| [`../ansible/dev/playbooks/vault/vault_vip.yml`](../ansible/dev/playbooks/vault/vault_vip.yml) | Keepalived VIP management (`10.0.52.100`) |
| [`../ansible/dev/playbooks/vault/vault-trust-aws.yml`](../ansible/dev/playbooks/vault/vault-trust-aws.yml) | Enables AWS Secrets Engine, configures `vault_trust` root config, creates `etcd-backup` role |
| [`../ansible/dev/playbooks/vault/templates/vault.hcl.j2`](../ansible/dev/playbooks/vault/templates/vault.hcl.j2) | Vault server config template (TLS listener, Raft, AWS KMS seal) |
| [`../ansible/dev/playbooks/vault/templates/vault.env.j2`](../ansible/dev/playbooks/vault/templates/vault.env.j2) | systemd EnvironmentFile template (AWS KMS credentials) |
| [`../ansible/dev/playbooks/vault/templates/vault-keepalived.conf.j2`](../ansible/dev/playbooks/vault/templates/vault-keepalived.conf.j2) | Keepalived config template |
| [`../ansible/dev/playbooks/vault/README.md`](../ansible/dev/playbooks/vault/README.md) | 15 architectural decisions, deployment steps, troubleshooting links |
| [`../ansible/dev/playbooks/vault/crt-change.txt`](../ansible/dev/playbooks/vault/crt-change.txt) | Chronological cert-change log |
| [`../ansible/dev/playbooks/k8s/integration-vault-k8s-trust.yml`](../ansible/dev/playbooks/k8s/integration-vault-k8s-trust.yml) | Configures Vault's Kubernetes auth method (registers token reviewer JWT) |
| [`../ansible/dev/playbooks/freeipa/add_dns_records.yml`](../ansible/dev/playbooks/freeipa/add_dns_records.yml) | Adds `vault.lab.local` VIP + `vault1/2/3.lab.local` DNS entries |
| [`../ansible/dev/inventory/group_vars/vault_cluster.yml`](../ansible/dev/inventory/group_vars/vault_cluster.yml) | AWS KMS creds (encrypted), LDAP bindpass, keepalived secret. Documents both credential-injection approaches |
| [`../ansible/dev/inventory/inventory.ini`](../ansible/dev/inventory/inventory.ini) | Dev inventory (vault_cluster group) |

**Prod:** same layout under [`../ansible/prod/playbooks/vault/`](../ansible/prod/playbooks/vault/), [`../ansible/prod/inventory/`](../ansible/prod/inventory/). Only differences: region (`eu-west-2`), IPs (`10.0.62.x`), VIP (`10.0.62.100`), AWS account.

### Layer 2 — Terraform (AWS, Proxmox LXC provisioning)

**Dev:**

| Path | Purpose |
|------|---------|
| [`../terraform/dev/aws/kms-vault-unseal/`](../terraform/dev/aws/kms-vault-unseal/) | AWS KMS key (`alias/vault-unseal`) + `vault_unseal` IAM user + Secrets Manager entries (`dev/vault/unseal-credentials`, `dev/vault/unseal-keys`) |
| [`../terraform/dev/aws/vault-trust/`](../terraform/dev/aws/vault-trust/) | `vault_trust` IAM user + `etcd-backup` IAM role + S3 bucket for etcd backups + Secrets Manager entry (`dev/vault/aws-secrets-engine-credentials`) |
| [`../terraform/dev/proxmox/lxc/vault_cluster/`](../terraform/dev/proxmox/lxc/vault_cluster/) | 3 LXC containers on Proxmox (vault1/2/3), local-lvm storage per node |

**Prod:** same layout under [`../terraform/prod/aws/kms-vault-unseal/`](../terraform/prod/aws/kms-vault-unseal/), [`../terraform/prod/aws/vault-trust/`](../terraform/prod/aws/vault-trust/), [`../terraform/prod/proxmox/lxc/vault_cluster/`](../terraform/prod/proxmox/lxc/vault_cluster/).

### Layer 3 — Kubernetes (Vault Agent Injector + app integrations)

**Infrastructure (both envs):**

| Path | Purpose |
|------|---------|
| [`../kubernetes/dev/deployments/infrastructure/vault/vault.yaml`](../kubernetes/dev/deployments/infrastructure/vault/vault.yaml) | Vault Agent Injector HelmRelease (chart v0.32.0, server disabled, injector enabled with 2 replicas on control-plane nodes, anti-affinity required) + HelmRepository |
| [`../kubernetes/dev/deployments/infrastructure/vault/vault-auth-sa.yaml`](../kubernetes/dev/deployments/infrastructure/vault/vault-auth-sa.yaml) | `vault-auth` SA in `kube-system` + token Secret + `system:auth-delegator` ClusterRoleBinding (used by Vault to token-review) |
| [`../kubernetes/dev/deployments/infrastructure/vault/kustomization.yaml`](../kubernetes/dev/deployments/infrastructure/vault/kustomization.yaml) | Kustomize wrapper |
| [`../kubernetes/prod/deployments/infrastructure/vault/`](../kubernetes/prod/deployments/infrastructure/vault/) | Prod mirror — identical pattern |

**Apps using Vault injection (dev):**

| App | Manifest | Notes |
|-----|----------|-------|
| WordPress | [`../kubernetes/dev/deployments/apps/wordpress/deployment.yaml`](../kubernetes/dev/deployments/apps/wordpress/deployment.yaml) + [`vault-ca-secret.yaml`](../kubernetes/dev/deployments/apps/wordpress/vault-ca-secret.yaml) | DB creds injected from `secret/data/wordpress/config` |
| MariaDB | [`../kubernetes/dev/deployments/apps/mariadb/statefulset.yaml`](../kubernetes/dev/deployments/apps/mariadb/statefulset.yaml) + [`vault-ca-secret.yaml`](../kubernetes/dev/deployments/apps/mariadb/vault-ca-secret.yaml) | Root + app DB creds |
| Grafana (kube-prometheus-stack) | [`../kubernetes/dev/deployments/apps/monitoring/helm-release.yaml`](../kubernetes/dev/deployments/apps/monitoring/helm-release.yaml) + [`vault-ca-secret.yaml`](../kubernetes/dev/deployments/apps/monitoring/vault-ca-secret.yaml) | Admin password, datasource credentials. SA name = chart-generated (see `[TS-K8S-014]`) |
| Alertmanager | [`../kubernetes/dev/deployments/apps/alertmanager/statefulset.yaml`](../kubernetes/dev/deployments/apps/alertmanager/statefulset.yaml) | Alert notification credentials (dev only currently) |
| Remediation controller | [`../kubernetes/dev/deployments/apps/remediation/deployment.yaml`](../kubernetes/dev/deployments/apps/remediation/deployment.yaml) + [`vault-ca-secret.yaml`](../kubernetes/dev/deployments/apps/remediation/vault-ca-secret.yaml) + [`SETUP.md`](../kubernetes/dev/deployments/apps/remediation/SETUP.md) + [`BLUEPRINT.md`](../kubernetes/dev/deployments/apps/remediation/BLUEPRINT.md) | Proxmox API creds, other sensitive inputs |
| etcd-backup CronJob | [`../kubernetes/dev/deployments/apps/etcd-backup/cronjob.yaml`](../kubernetes/dev/deployments/apps/etcd-backup/cronjob.yaml) + [`vault-ca-secret.yaml`](../kubernetes/dev/deployments/apps/etcd-backup/vault-ca-secret.yaml) | Uses AWS Secrets Engine (`aws/creds/etcd-backup`) for temp AWS creds — see [`etcd-backup-role.md`](etcd-backup-role.md). Runs in `kube-system` — required injector RBAC change (`[TS-K8S-017]`) |
| nginx test app | [`../kubernetes/dev/deployments/apps/testing/nginx-test/nginx-test.yaml`](../kubernetes/dev/deployments/apps/testing/nginx-test/nginx-test.yaml) + [`vault-ca-secret.yaml`](../kubernetes/dev/deployments/apps/testing/nginx-test/vault-ca-secret.yaml) | Smoke test for injection pattern |

**Apps using Vault injection (prod):** same list **except** alertmanager (dev-only today), under [`../kubernetes/prod/deployments/apps/`](../kubernetes/prod/deployments/apps/).

**Kubernetes docs (cross-env):**

| Path | Purpose |
|------|---------|
| [`../kubernetes/docs/vault-pod-setup.sh`](../kubernetes/docs/vault-pod-setup.sh) | Interactive helper — creates Vault policy, role, and secrets for a new app |
| [`../kubernetes/docs/vault-k8s-pre-setup.txt`](../kubernetes/docs/vault-k8s-pre-setup.txt) | Pre-setup notes (K8s cluster info, CA cert extraction, token reviewer JWT setup, OIDC issuer config) |

### Layer 4 — Troubleshooting (incidents, investigations)

**Vault-specific cases:**

| # | Path | Summary |
|---|------|---------|
| Index | [`../troubleshooting/vault/README.md`](../troubleshooting/vault/README.md) | Table of all Vault TS cases |
| 1 | [`../troubleshooting/vault/1-vault-cluster-initial-setup-investigation.md`](../troubleshooting/vault/1-vault-cluster-initial-setup-investigation.md) | 8 issues during initial setup (GPG, Certmonger `--force`, CSR mismatch, permissions, TLS IP SAN, shell expansion, RPM ordering) |
| 2 | [`../troubleshooting/vault/2-freeipa-vip-certificate-san-managedby.md`](../troubleshooting/vault/2-freeipa-vip-certificate-san-managedby.md) | VIP cert — `service-mod` vs `service-add-managedby`. See [`cert-regen-cascade.md`](cert-regen-cascade.md) |
| 3 | [`../troubleshooting/vault/3-vault-kms-credentials-overwrite-empty-vars.md`](../troubleshooting/vault/3-vault-kms-credentials-overwrite-empty-vars.md) | Empty KMS creds on manual Ansible run → added `when:` gate. See [`kms-unseal.md`](kms-unseal.md) |
| 4 | [`../troubleshooting/vault/4-vault-agent-injector-k8s-tls-ca-setup.md`](../troubleshooting/vault/4-vault-agent-injector-k8s-tls-ca-setup.md) | Agent sidecar TLS CA annotation + Go template hyphen handling |
| 5 | [`../troubleshooting/vault/5-vault-node-recovery-stale-raft-data.md`](../troubleshooting/vault/5-vault-node-recovery-stale-raft-data.md) | Stale `vault.db` prevents rejoin; fix = remove `raft/` AND `vault.db` |

**k8s cases that touch Vault:**

| # | Path | Summary |
|---|------|---------|
| 14 | [`../troubleshooting/kubernetes/14-vault-k8s-auth-service-account-not-authorized.md`](../troubleshooting/kubernetes/14-vault-k8s-auth-service-account-not-authorized.md) | SA name mismatch (Helm-generated vs Vault role bind) |
| 17 | [`../troubleshooting/kubernetes/17-vault-injection-system-namespace-denied.md`](../troubleshooting/kubernetes/17-vault-injection-system-namespace-denied.md) | Injector blocked in `kube-system`; required RBAC change |
| 24 | [`../troubleshooting/kubernetes/24-vault-cluster-resilience-2-node-quorum.md`](../troubleshooting/kubernetes/24-vault-cluster-resilience-2-node-quorum.md) | 2-node Raft = no quorum = no writes |
| 25 | [`../troubleshooting/kubernetes/25-promtail-vault-namespace-logs.md`](../troubleshooting/kubernetes/25-promtail-vault-namespace-logs.md) | Promtail scraping Vault namespace logs |
| 33 | [`../troubleshooting/kubernetes/33-vault-agent-dns-failure-new-pod-blocking.md`](../troubleshooting/kubernetes/33-vault-agent-dns-failure-new-pod-blocking.md) | IPA DNS down → Vault Agent can't resolve `vault.lab.local` → new pods stuck in Init |
| 34 | [`../troubleshooting/kubernetes/34-wordpress-external-dns-slowness.md`](../troubleshooting/kubernetes/34-wordpress-external-dns-slowness.md) | Related to 33 — IPA-adjacent slowness |
| 35 | [`../troubleshooting/kubernetes/35-pod-restart-investigation-ipa-down.md`](../troubleshooting/kubernetes/35-pod-restart-investigation-ipa-down.md) | Pod restarts during IPA outage |

**Identity/FreeIPA cases relevant to Vault:**

| # | Path | Why it matters for Vault |
|---|------|-------------------------|
| 1 | [`../troubleshooting/identity/1-lxc-kerberos-keyring-auth-failure.md`](../troubleshooting/identity/1-lxc-kerberos-keyring-auth-failure.md) | Vault nodes are IPA-enrolled LXC; Kerberos issues block Certmonger cert requests |
| 2 | [`../troubleshooting/identity/2-freeipa-dns-configuration-issues.md`](../troubleshooting/identity/2-freeipa-dns-configuration-issues.md) | Vault uses `vault.lab.local` DNS — IPA DNS health is a hard dependency |
| 5 | [`../troubleshooting/identity/5-freeipa-server-sssd-sudo.md`](../troubleshooting/identity/5-freeipa-server-sssd-sudo.md) | Vault admin SSH via FreeIPA-managed sudo |
| 6 | [`../troubleshooting/identity/6-freeipa-lxc-uid-range-investigation.md`](../troubleshooting/identity/6-freeipa-lxc-uid-range-investigation.md) | LXC UID remapping — affects Vault LXC enrollment |
| 8 | [`../troubleshooting/identity/8-keytab-preauthentication-failed.md`](../troubleshooting/identity/8-keytab-preauthentication-failed.md) | Vault node keytab for FreeIPA enrollment |

### Layer 5 — Disaster Recovery (tests + dependency docs)

| Path | Purpose |
|------|---------|
| [`../disaster-recovery/README.md`](../disaster-recovery/README.md) | DR hub — test summary, known SPOFs |
| [`../disaster-recovery/vault-single-node-down.md`](../disaster-recovery/vault-single-node-down.md) | Vault with one node down — quorum still holds |
| [`../disaster-recovery/vault-quorum-loss.md`](../disaster-recovery/vault-quorum-loss.md) | Complete quorum loss recovery path |
| [`../disaster-recovery/vault-aws-kms-dependency.md`](../disaster-recovery/vault-aws-kms-dependency.md) | AWS KMS unavailable — documents manual-unseal fallback. Covers the `vault.env` credential flow end-to-end |
| [`../disaster-recovery/etcd-backup-s3.md`](../disaster-recovery/etcd-backup-s3.md) | Tests etcd backup CronJob → Vault AWS Secrets Engine → STS → S3 end to end |
| [`../disaster-recovery/ipa-domain-down-dr-test.md`](../disaster-recovery/ipa-domain-down-dr-test.md) | FreeIPA down — cascading impact on Vault (DNS, certs, service principals) |
| [`../disaster-recovery/proxmox-vzdump-backup.md`](../disaster-recovery/proxmox-vzdump-backup.md) | Proxmox LXC backup — applies to Vault containers |

### Layer 6 — Deployment guides (setup walkthroughs)

| Path | Purpose |
|------|---------|
| [`../deployment-docs/vault-initial-setup-guide.txt`](../deployment-docs/vault-initial-setup-guide.txt) | Complete 5-phase setup (golden template → LXC → Vault service → KMS → K8s integration) |
| [`../deployment-docs/vault-k8s-integration-guide.txt`](../deployment-docs/vault-k8s-integration-guide.txt) | Kubernetes auth setup, injector deployment, app policy/role creation |
| [`../deployment-docs/k8s-etcd-vault-aws-integration.txt`](../deployment-docs/k8s-etcd-vault-aws-integration.txt) | Full etcd backup integration (Terraform → Vault config → K8s CronJob) |
| [`../deployment-docs/aws-secrets-setup-guide.txt`](../deployment-docs/aws-secrets-setup-guide.txt) | Prereq — AWS Secrets Manager entries the workflows depend on |
| [`../deployment-docs/freeipa-initial-setup-guide.txt`](../deployment-docs/freeipa-initial-setup-guide.txt) | Prereq — FreeIPA (Vault's cert + DNS dependency) |
| [`../deployment-docs/signal-flows/vault-k8s-auth-signal-flow.txt`](../deployment-docs/signal-flows/vault-k8s-auth-signal-flow.txt) | Signal-flow diagram — pod → Agent → Vault K8s auth → token → secret |
| [`../deployment-docs/signal-flows/flux.txt`](../deployment-docs/signal-flows/flux.txt) | Flux signal flow — includes Vault Agent Injector deployment path |

### Layer 7 — GitHub Actions (automation)

| Path | Purpose |
|------|---------|
| [`../.github/workflows/dev-vault-full-setup.yml`](../.github/workflows/dev-vault-full-setup.yml) | 2-job: Terraform (LXC) then Ansible (vault_setup). Pulls unseal creds from AWS SM, runs vault_setup playbook with Kerberos |
| [`../.github/workflows/prod-vault-full-setup.yml`](../.github/workflows/prod-vault-full-setup.yml) | Prod equivalent |
| [`../.github/workflows/dev-aws-kms-vault-unseal.yml`](../.github/workflows/dev-aws-kms-vault-unseal.yml) | Terraform apply for KMS module (dev) |
| [`../.github/workflows/prod-aws-kms-vault-unseal.yml`](../.github/workflows/prod-aws-kms-vault-unseal.yml) | Terraform apply for KMS module (prod) |
| [`../.github/workflows/dev-aws-vault-trust.yml`](../.github/workflows/dev-aws-vault-trust.yml) | Terraform apply for vault-trust module (dev) |
| [`../.github/workflows/prod-aws-vault-trust.yml`](../.github/workflows/prod-aws-vault-trust.yml) | Terraform apply for vault-trust module (prod) |

### Layer 8 — Network (VIP, DNS, firewall)

| Path | Purpose |
|------|---------|
| [`../network/ip-planning.txt`](../network/ip-planning.txt) | Defines Vault node IPs + VIPs: Dev `10.0.52.10-12` + VIP `10.0.52.100`; Prod `10.0.62.10-12` + VIP `10.0.62.100`; both resolve to `vault.lab.local` |
| [`../network/DESIGN.md`](../network/DESIGN.md) | VLAN architecture — Vault cluster in its own VLAN, firewall boundaries documented |
| [`../network/router/mikrotik/phase2-dev-services.rsc`](../network/router/mikrotik/phase2-dev-services.rsc) | MikroTik router config — includes Vault VLAN rules |

### Layer 9 — Archive / POC reference

| Path | Purpose |
|------|---------|
| [`../archive-poc-v1/automation/ansible/vault/`](../archive-poc-v1/automation/ansible/vault/) | Historical POC Vault setup — raft + NO TLS, no VIP, no KMS. Contrast against current to see the evolution (see [`DESIGN.md`](DESIGN.md) "Starting point") |
| [`../archive-poc-v1/automation/ansible/vault/vault.hcl.j2`](../archive-poc-v1/automation/ansible/vault/vault.hcl.j2) | Original HCL template — plain HTTP listener, no KMS seal, direct node IPs |

---

## Cross-cutting concerns worth knowing

### The FreeIPA ↔ Vault entanglement

Vault has **four** hard dependencies on FreeIPA. When FreeIPA has a bad day, Vault has a bad day:

1. **DNS** — `vault.lab.local` and `vault1/2/3.lab.local` all resolve via IPA DNS. If IPA DNS is down, nothing inside the cluster (or inside any IPA-joined machine) can reach Vault. See [`../troubleshooting/kubernetes/33-vault-agent-dns-failure-new-pod-blocking.md`](../troubleshooting/kubernetes/33-vault-agent-dns-failure-new-pod-blocking.md).
2. **TLS certificates** — Vault's TLS certs are issued by the IPA CA. Renewal requires FreeIPA to be available.
3. **Service principals** — each Vault node is enrolled as an IPA host; cert operations use the host keytab for Kerberos auth against IPA.
4. **LDAP authentication** — Vault's LDAP auth method points at IPA. If LDAP is down, human admins can't log into Vault (breakglass userpass still works).

Documented as a **known SPOF** in [`../disaster-recovery/README.md`](../disaster-recovery/README.md). Mitigation today = "don't take FreeIPA down without planning." No automated failover.

### The AWS dependency

Vault has **two** hard dependencies on AWS:

1. **KMS for auto-unseal** — Vault can't unseal without KMS reachable. Fallback: manual unseal with recovery keys from AWS Secrets Manager. See [`kms-unseal.md`](kms-unseal.md).
2. **AWS Secrets Engine for etcd backup** — the `vault_trust` user's AWS calls. If AWS is unreachable, the etcd-backup CronJob fails (new snapshots don't upload); existing credentials in-flight stay valid until their 1h TTL.

Less concerning than the FreeIPA dependency because AWS is more reliable than my FreeIPA instance, but it's real. See [`../disaster-recovery/vault-aws-kms-dependency.md`](../disaster-recovery/vault-aws-kms-dependency.md).

### The Vault ↔ everything dependency

Vault is a dependency for almost every workload in the cluster. When Vault is unavailable:

- Existing pods: keep running until their cached Vault token expires (typically 1h)
- New pods: can't start if they have the inject annotation — stuck in `Init:0/1`
- etcd backups: next scheduled run fails to get AWS creds, no snapshot produced
- Database password rotation: manual rotation requires Vault to be writable
- Admin operations: LDAP login requires IPA → Vault → break-glass userpass

This is captured in the "Known SPOFs" list at [`../disaster-recovery/README.md`](../disaster-recovery/README.md). Vault's own 3-node HA protects against single-node failure; the 2-node quorum loss scenario (`[TS-K8S-024]`) is the class of failure that brings it down.

---

## How to keep this file current

This map is only useful if it stays accurate. Signals that it needs updating:

- A new app gets wired to Vault injection → add a row to Layer 3's app table
- A new TS case about Vault is written → add to Layer 4
- A new DR test targets Vault → add to Layer 5
- A new Ansible playbook, Terraform module, or GitHub workflow is added for Vault → add to the appropriate layer
- An IP / VIP / region / account changes → update Layer 8 and cross-check Layer 1/2

Check the "Last verified" date at the top. If it's more than a few months old when you're reading this, run `git log --oneline kubernetes/ ansible/ terraform/ .github/workflows/ troubleshooting/ disaster-recovery/ deployment-docs/ network/ -- "*vault*" "*unseal*" "*kms*"` to see what's moved since and update accordingly.
