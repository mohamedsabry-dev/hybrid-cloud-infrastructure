# Troubleshooting Cases

Documentation of issues encountered and resolved during infrastructure setup.

Each subfolder contains troubleshooting tickets numbered sequentially within that category.

---

## Categories

| Folder | Tickets | Range | Description |
|--------|---------|-------|-------------|
| [aws/](aws/) | 1 | 1 | AWS CloudFormation, IAM issues |
| [github/](github/) | 3 | 1-3 | GitHub runners, workflows, git operations |
| [github-actions/](github-actions/) | 5 | 1-5 | CI/CD workflow issues, cleanup |
| [identity/](identity/) | 8 | 1-8 | FreeIPA, Kerberos, authentication |
| [kubernetes/](kubernetes/) | 5 | 1-5 | K8s cluster, pods, networking, storage |
| [linux/](linux/) | 5 | 1-5 | OS-level issues (Rocky Linux, NTP, UID) |
| [macos/](macos/) | 2 | 1-2 | macOS client configuration |
| [network/](network/) | 9 | 1-9 | Routing, WireGuard, hardware issues |
| [proxmox/](proxmox/) | 11 | 1-11 | Proxmox VE platform, VMs, LXC, NFS |
| [security/](security/) | 1 | 1 | Secrets management, incidents |
| [terraform/](terraform/) | 9 | 1-9 | Terraform IaC, Proxmox provider |
| [vault/](vault/) | 11 | 1-11 | HashiCorp Vault, certificates, Ansible |

---

**Total: 70 troubleshooting tickets across 12 categories**

---

## Naming Convention

Files follow the format: `N-short-description.md`

- `N` = sequential number within the subfolder (1, 2, 3...)
- Each subfolder maintains its own numbering sequence
- Numbers are assigned chronologically as tickets are added

## Adding New Tickets

1. Identify the appropriate category folder
2. Find the next available number in that folder
3. Create file: `N-short-description.md`
4. Include: Symptom, Root Cause, Solution, Prevention
