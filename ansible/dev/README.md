# Ansible — DEV Environment

Ansible configuration for the DEV environment. Configures the full node
lifecycle after Terraform provisioning — bootstrap (before FreeIPA exists),
domain join, Vault HA cluster, Kubernetes node prep + cluster init + Flux
bootstrap, Nginx reverse proxy, and the self-hosted GitHub Actions runner.

For the dev/prod split rationale see [`../README.md`](../README.md).
For day-to-day ops (keytab setup, git workflow, utility commands) see
[`operation_guide.txt`](operation_guide.txt).
For the Ansible Vault (encryption at rest) commands see
[`ansible-vault-guide.txt`](ansible-vault-guide.txt).

---

## Directory layout

```
ansible/dev/
├── README.md                        # this file — scope + navigation
├── ansible.cfg                      # default inventory + vault password file path
├── operation_guide.txt              # day-to-day ops (kinit, SSH cleanup, testing)
├── ansible-vault-guide.txt          # encrypt/view/edit/rekey commands
├── inventory/
│   ├── inventory.ini                # Production inventory (FQDN, Kerberos, super_bot)
│   ├── first_setup_inventory.ini    # Bootstrap inventory (IP, root + SSH key)
│   └── group_vars/
│       ├── all.yml                  # shared vars (ipaclient_*, ipaadmin_password, etc.)
│       ├── freeipa.yml              # FreeIPA host groups + bot/admin users + encrypted passwords
│       ├── vault_cluster.yml        # AWS KMS creds + bindpass (env-var lookup OR ansible-vault)
│       └── k8s_masters.yml          # k8s master-specific vars
├── examples/                        # manual ops + usage examples (e.g., vault/usage.md)
└── playbooks/
    ├── ansible/                     # set up the Ansible control node
    ├── common/                      # cross-platform tasks (pre_setup, ntp)
    ├── freeipa/                     # identity / domain / DNS / LXC krb5 fix
    ├── vault/                       # Vault HA cluster deploy + config
    ├── k8s/                         # K8s cluster bootstrap + Flux + Vault-K8s trust
    ├── nginx/                       # external Nginx reverse proxy
    └── local-runner/                # self-hosted GH runner tooling
```

## Host groups

| Group | Type | VLAN | Purpose |
|-------|------|------|---------|
| `freeipa` | VM | 60 | Identity / DNS server |
| `k8s_masters` | VM | 61 | Kubernetes control plane |
| `k8s_workers` | VM | 64 | Kubernetes workers |
| `vault_cluster` | LXC | 62 | HashiCorp Vault HA cluster |
| `ansible` | LXC | 63 | Ansible control node (local connection) |
| `local_runners` | LXC | 63 | GitHub Actions self-hosted runners |
| `nginx` | LXC | 65 | External reverse proxy |

**Meta groups:** `k8s` (masters + workers), `managed_hosts` (all except freeipa), `vms`, `lxc`.

## Two inventories

| File | User | Addressing | When |
|------|------|------------|------|
| `inventory.ini` | `super_bot` + Kerberos | FQDN via FreeIPA DNS | Normal operation after FreeIPA is up |
| `first_setup_inventory.ini` | `root` + SSH key | Raw IPs | Bootstrap (before FreeIPA) AND DR fallback when FreeIPA is down |

Workflows that use the bootstrap inventory: `{env}-freeipa-full-setup.yml`,
`{env}-ansible-full-setup.yml`, `{env}-local-runner-full-setup.yml`.

Rationale (dual-inventory pattern, LXC Kerberos fixes, NTP-skipped-on-LXC, UID range 60001-65500) lives in [`../../freeipa/` — no longer present, folded into `deployment-docs/freeipa-overview.md`](../../deployment-docs/freeipa-overview.md).

## Playbook folders

Each has its own README:

| Folder | Focus |
|--------|-------|
| [`playbooks/ansible/`](playbooks/ansible/) | Ansible node setup, Galaxy collections |
| [`playbooks/common/`](playbooks/common/) | `pre_setup.yml` (mirror fix + SSH auth + packages), `ntp.yml` |
| [`playbooks/freeipa/`](playbooks/freeipa/) | FreeIPA install + domain config + host enrollment + LXC krb5 fix + DNS fallback |
| [`playbooks/vault/`](playbooks/vault/) | 3-node Vault HA cluster with TLS + KMS unseal + VIP |
| [`playbooks/k8s/`](playbooks/k8s/) | K8s cluster init, HAProxy+Keepalived, Flux bootstrap, NFS mounts |
| [`playbooks/nginx/`](playbooks/nginx/) | Catch-all reverse proxy forwarding `*.lab.local` to workers:30080 |
| [`playbooks/local-runner/`](playbooks/local-runner/) | Runner LXC tools (Docker, kubectl, etc.) |

## Secrets split

- **Ansible Vault** — encrypted values in `group_vars/` (`ipaadmin_password`, `default_admin_user_password`, `default_bot_user_password`, `vault_aws_*_key` fallback). Used at bootstrap time before HashiCorp Vault is running.
- **AWS Secrets Manager** — runtime creds fetched by GitHub workflows (Proxmox tokens, Vault KMS unseal keys, super_bot keytab).

Encrypt/view/edit commands: see [`ansible-vault-guide.txt`](ansible-vault-guide.txt).

## VLAN reference

| VLAN | Subnet | Purpose |
|------|--------|---------|
| 60 | 10.0.60.0/24 | FreeIPA / Identity |
| 61 | 10.0.61.0/24 | K8s Masters |
| 62 | 10.0.62.0/24 | Vault Cluster |
| 63 | 10.0.63.0/24 | Ansible / Runners |
| 64 | 10.0.64.0/24 | K8s Workers |
| 65 | 10.0.65.0/24 | Nginx / Proxy |

Prod equivalents are in VLANs 50-55. Full plan: [`../../network/ip-planning.txt`](../../network/ip-planning.txt).

## Related

- [`operation_guide.txt`](operation_guide.txt) — day-to-day (kinit, testing, SSH known_hosts cleanup)
- [`ansible-vault-guide.txt`](ansible-vault-guide.txt) — ansible-vault CLI commands
- [`../README.md`](../README.md) — Ansible parent scope (both envs)
- [`../../deployment-docs/freeipa-overview.md`](../../deployment-docs/freeipa-overview.md) — full identity-layer story
- [`../../deployment-docs/vault-overview.md`](../../deployment-docs/vault-overview.md) — full Vault system story
- [`../../troubleshooting/identity/`](../../troubleshooting/identity/) — identity / Kerberos / LDAP TS cases
- [`../../.github/workflows/`](../../.github/workflows/) — workflows that invoke these playbooks
