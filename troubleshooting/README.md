# Troubleshooting Cases

Documentation of issues encountered and resolved during hybrid cloud infrastructure setup and operations.

Each subfolder contains troubleshooting tickets numbered sequentially within that category.

---

## Categories

| Folder | Cases | Description |
|--------|-------|-------------|
| [aws/](aws/) | 1 | AWS CloudFormation, IAM |
| [github/](github/) | 10 | GitHub Actions, runners, workflows, git operations |
| [identity/](identity/) | 9 | FreeIPA, Kerberos, SSSD, authentication |
| [kubernetes/](kubernetes/) | 49 | K8s cluster, pods, networking, storage, GitOps |
| [linux/](linux/) | 4 | OS-level issues (Rocky Linux, NTP) |
| [macos/](macos/) | 2 | macOS client configuration |
| [network/](network/) | 5 | Routing, WireGuard, network stability |
| [proxmox/](proxmox/) | 17 | Proxmox VE, VMs, LXC, backups, NFS, metrics |
| [terraform/](terraform/) | 11 | Terraform IaC, Proxmox provider, cloud-init |
| [vault/](vault/) | 5 | HashiCorp Vault, certificates, K8s integration |

---

**Total: 113 troubleshooting cases across 10 categories**

---

## Template Structure

All cases follow a standardized 9-point template:

| Section | Description |
|---------|-------------|
| **1. Context** | System, environment, related components |
| **2. Issue** | Symptom, error messages, impact |
| **3. Analysis** | Investigation steps with commands/outputs |
| **4. Root Cause** | Why the issue occurred |
| **5. Solution** | Fix steps, files changed, prevention |
| **6. Solution Risk** | Risk level, potential impact |
| **7. Impact After Fix** | Observed results |
| **8. Notes** | Lessons learned, commands reference |
| **9. Workaround** | Temporary fixes if needed |

**Header Format:** `# TS-XXX-NNN | YYYY-MM-DD | STATUS`

---

## Quick Stats by Category

```
kubernetes/  █████████████████████████████████████████████████  49
proxmox/     █████████████████                                 17
terraform/   ███████████                                       11
github/      ██████████                                        10
identity/    █████████                                          9
network/     █████                                              5
vault/       █████                                              5
linux/       ████                                               4
macos/       ██                                                 2
aws/         █                                                  1
```

---

## Naming Convention

Files follow the format: `N-short-description.md`

- `N` = sequential number within the subfolder
- Numbers assigned chronologically by incident date
- Each subfolder maintains its own sequence

---

## Status Definitions

| Status | Meaning |
|--------|---------|
| RESOLVED | Issue fixed, root cause identified |
| IN PROGRESS | Investigation or fix ongoing |
| MONITORING | Workaround applied, watching for recurrence |
| SUSPENDED | Partially investigated, paused for later |
| DOCUMENTED | Design/behavior documented, no fix needed |
| OPEN | Issue identified, not yet resolved |

---

## Adding New Cases

1. Identify the appropriate category folder
2. Find the next available number in that folder
3. Create file: `N-short-description.md`
4. Follow the 9-point template structure
5. Update the category README if exists
6. Update this README with new count

---

## Environment Overview

| Component | Technology |
|-----------|------------|
| Virtualization | Proxmox VE |
| IaC | Terraform |
| GitOps | Flux CD |
| Containers | Kubernetes (kubeadm) |
| CNI | Calico |
| Storage | NFS + CSI Driver |
| Identity | FreeIPA |
| Secrets | HashiCorp Vault |
| CI/CD | GitHub Actions |
| Monitoring | Prometheus + Grafana + Loki |
