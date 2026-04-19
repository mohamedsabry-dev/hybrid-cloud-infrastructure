# Ansible — Hybrid Cloud Infrastructure

Ansible configuration management for the hybrid cloud infrastructure. It handles the full post-provisioning lifecycle — FreeIPA identity and DNS, HashiCorp Vault HA cluster, Kubernetes node preparation and init, Nginx reverse proxy, self-hosted GitHub Actions runners, and common cross-platform tasks — across a mix of VMs and LXC containers living on Proxmox.

Terraform provisions the hosts; Ansible configures them once they exist.

> **Design notes & reasoning** — for why `dev/` and `prod/` are kept as two fully separate folders instead of a shared codebase with env flags, see [`DESIGN.md`](DESIGN.md).

---

## What Ansible manages here

| Playbook folder | Responsibility |
|-----------------|----------------|
| `playbooks/ansible/` | Set up the Ansible control node itself — packages, Galaxy collections. |
| `playbooks/common/` | Cross-platform tasks: pre-setup (mirror fix + SSH auth + packages), NTP/Chrony per host type, break-glass user (TODO), Node Exporter install. |
| `playbooks/freeipa/` | Install FreeIPA server, configure the domain, enroll managed hosts, add DNS records, fix LXC Kerberos keyring, DNS fallback. |
| `playbooks/vault/` | Deploy the 3-node HashiCorp Vault HA cluster with AWS KMS auto-unseal, TLS certs from FreeIPA, VIP via Keepalived, and AWS-trust integration for the AWS Secrets Engine. |
| `playbooks/k8s/` | Initialize and configure the Kubernetes cluster (masters + workers), HAProxy + Keepalived for API HA, Flux bootstrap, worker NFS mounts, tools install, hosts fallback, Vault–k8s trust. |
| `playbooks/nginx/` | Configure the external Nginx reverse proxy used for cluster ingress routing. |
| `playbooks/local-runner/` | Install tooling on the self-hosted GitHub Actions runner LXC (Docker, kubectl, etc.). |

Each playbook folder has its own `README.md` with playbook-by-playbook detail.

---

## Shared architecture (common to both dev and prod)

### Two-phase inventory approach

Every environment has two inventory files:

- `first_setup_inventory.ini` — IP-based, `root` user, no FreeIPA dependency. Used during bootstrap (before the domain exists) and as the DR fallback (if FreeIPA is down).
- `inventory.ini` — FQDN hostnames, `super_bot` domain user, Kerberos/GSSAPI auth. Used for normal day-to-day operation after FreeIPA is up.

The full reasoning for this split — including which workflows use which, and the rule of thumb that "anything using `first_setup_inventory.ini` is running before the domain and keytabs exist" — is in [`dev/README.md`](dev/README.md) and [`prod/README.md`](prod/README.md).

### Group topology

7 host groups mapped to 6 VLANs per environment:

| Group | Type | Purpose |
|-------|------|---------|
| `freeipa` | VM | Identity / DNS server |
| `k8s_masters` | VM | Kubernetes control plane |
| `k8s_workers` | VM | Kubernetes workloads |
| `vault_cluster` | LXC | HashiCorp Vault HA |
| `ansible` | LXC | Ansible control node |
| `local_runners` | LXC | Self-hosted GH Actions runners |
| `nginx` | LXC | External reverse proxy |

Meta groups simplify targeting: `vms`, `lxc`, `k8s` (masters + workers), `managed_hosts` (everything except the FreeIPA server).

Env-specific VLAN numbers (dev uses 60s, prod uses 50s) are listed in each env's README.

### Secrets handling (two-layer)

1. **Ansible Vault** encrypts sensitive values at rest inside `group_vars/` — FreeIPA admin password, default user passwords, AWS KMS backup keys. This exists because HashiCorp Vault isn't deployed yet during the initial bootstrap phase; we need *something* to encrypt secrets before Vault comes online.
2. **AWS Secrets Manager** holds runtime credentials fetched at workflow time — Proxmox API tokens, KMS unseal access keys, the `super_bot` keytab. GitHub Actions workflows `aws secretsmanager get-secret-value`, mask immediately, then inject via `GITHUB_ENV` / `TF_VAR_*`. Nothing is committed to git.

Once HashiCorp Vault is running, some of the Ansible Vault secrets could be migrated — that's a consolidation-phase decision I haven't made yet.

### FreeIPA as identity + DNS + Kerberos

Every managed host is enrolled into the `LAB.LOCAL` realm. The `super_bot` user is the automation service account, with HBAC and sudo rules defined in `playbooks/freeipa/domain_config.yml`. Keytabs live in AWS Secrets Manager and are fetched per workflow run, `kinit`-ed, then destroyed — so Kerberos credentials never touch disk persistently.

FreeIPA was configured with a custom UID range (60001–65500) to fit inside LXC unprivileged container UID mapping. Full reasoning: [`/troubleshooting/identity/6-freeipa-lxc-uid-range-investigation.md`](../troubleshooting/identity/6-freeipa-lxc-uid-range-investigation.md).

### `ansible.cfg` is environment-scoped

Each env has its own `ansible.cfg` with the correct default inventory and vault password file path. On the Ansible control node the operator exports `ANSIBLE_CONFIG=/srv/repo/ansible/{env}/ansible.cfg` in `~/.bashrc` so it survives shells and reboots — this is documented per env in `operation_guide.txt`.

---

## Where to look next

| What you want | Where |
|---------------|-------|
| Env-specific setup (dev) | [`dev/README.md`](dev/README.md) |
| Env-specific setup (prod) | [`prod/README.md`](prod/README.md) |
| Playbook-by-playbook details | `{env}/playbooks/<area>/README.md` inside each folder |
| Day-to-day ops (keytab, git, utilities) | `{env}/operation_guide.txt` |
| CI/CD workflows that run these playbooks | [`../.github/workflows/`](../.github/workflows/) |
| Troubleshooting incidents | [`../troubleshooting/`](../troubleshooting/) (identity, linux, vault, kubernetes, etc.) |
| Disaster-recovery runbooks | [`../disaster-recovery/`](../disaster-recovery/) |

---
