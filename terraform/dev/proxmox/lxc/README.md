# Proxmox LXC Containers — DEV

Terraform modules for provisioning LXC containers on Proxmox: the golden
template source, the Ansible control node, the self-hosted GitHub runner,
the external Nginx, and the 3-node Vault cluster.

LXC uses a different template pattern than VMs (vzdump template file, not
clone-from-ID) — see [`DESIGN.md`](DESIGN.md) for why. For setup + refresh
commands see [`golden-template-operation-guide.txt`](golden-template-operation-guide.txt).

---

## Modules

| Module | Description | Tags |
|--------|-------------|------|
| `golden-template` | Base Rocky Linux LXC source container (used to create the template file) | `lxc, golden, template, dev` |
| `ansible` | Ansible control node for configuration management | `lxc, ansible, automation, dev` |
| `local_runner` | Self-hosted GitHub Actions runner (internal, on-prem) | `lxc, runner, cicd, dev` |
| `nginx` | External reverse proxy / load balancer | `lxc, nginx, proxy, dev` |
| `vault_cluster` | HashiCorp Vault HA cluster (3 nodes, raft) | `lxc, vault, security, dev` |

Template flow: `golden-template` (LXC 9010) → `vzdump` to
`rocky-9-lxc-golden.tar.gz` on `nas-iso` → other modules reference the
file_id.

## Tags convention

Every container is tagged `[type, service, category, environment]`:

- `type` — always `lxc`
- `service` — service name (`ansible`, `nginx`, `vault`, `runner`, `golden`)
- `category` — functional category (`automation`, `proxy`, `security`, `cicd`, `template`)
- `environment` — `dev` or `prod`

## Module outputs

Every module exports the minimal identity set:

| Output | Description |
|--------|-------------|
| `container_id` | Proxmox container ID (CTID) |
| `name` | Container hostname |
| `ip` | Container IP address |

## Environment differences (dev vs prod)

Only `variables.tf` differs:

| Variable | Dev | Prod |
|----------|-----|------|
| `tags[3]` | `dev` | `prod` |
| `node_name` | `pve-dev` | `pve-prod` |
| `proxmox_api_url` | `https://pve-dev.lab.local:8006` | `https://pve-prod.lab.local:8006` |
| IP ranges | `10.0.6x.x` | `10.0.5x.x` |

## Related

- [`DESIGN.md`](DESIGN.md) — template-file pattern + provider limitation + hardcoded-values policy
- [`golden-template-operation-guide.txt`](golden-template-operation-guide.txt) — commands (setup, deploy, refresh)
- [`../vms/`](../vms/) — VMs (different template pattern: clone-from-ID)
- [`../../../../troubleshooting/proxmox/41-lxc-clone-vs-template-file-ssh-keys.md`](../../../../troubleshooting/proxmox/41-lxc-clone-vs-template-file-ssh-keys.md) — provider limitation TS case
- [`../../../../troubleshooting/terraform/`](../../../../troubleshooting/terraform/) — broader Terraform-Proxmox TS cases
