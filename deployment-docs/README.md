# Deployment Documentation

This folder contains setup guides for deploying the hybrid cloud infrastructure from scratch.

---

## Deployment Sequence

Follow these guides **in order**. Each step depends on the previous ones being complete.

| Order | Guide | Purpose |
|-------|-------|---------|
| 0 | [network-setup-guide.txt](network-setup-guide.txt) | Physical network (router, switch, AP) |
| 1 | [proxmox-setup-guide.txt](proxmox-setup-guide.txt) | Proxmox VE hypervisor installation |
| 2 | [aws-bootstrap-setup-guide.txt](aws-bootstrap-setup-guide.txt) | AWS OIDC, state bucket, IAM bootstrap |
| 3 | [github-setup-guide.txt](github-setup-guide.txt) | GitHub secrets, variables, runners |
| 4 | [aws-secrets-setup-guide.txt](aws-secrets-setup-guide.txt) | AWS Secrets Manager placeholders |
| 5 | [vpn-setup-guide.txt](vpn-setup-guide.txt) | WireGuard VPN to AWS |
| 6 | [ansible-runner-setup-guide.txt](ansible-runner-setup-guide.txt) | Ansible LXC + GitHub Runner LXC |
| 7 | [freeipa-initial-setup-guide.txt](freeipa-initial-setup-guide.txt) | FreeIPA identity management |
| 8 | [vault-initial-setup-guide.txt](vault-initial-setup-guide.txt) | HashiCorp Vault cluster |
| 9 | [k8s-initial-setup-guide.txt](k8s-initial-setup-guide.txt) | Kubernetes cluster |
| 10 | [vault-k8s-integration-guide.txt](vault-k8s-integration-guide.txt) | Vault-Kubernetes trust + secret injection |
| 11 | [nginx-setup-guide.txt](nginx-setup-guide.txt) | Nginx reverse proxy for K8s services |

---

## Quick Reference

### Infrastructure Prerequisites

Before deploying services, ensure these foundations are ready:

```
Physical Network (Step 0)
    └── Proxmox Servers (Step 1)
            └── AWS Bootstrap (Step 2)
                    └── GitHub Setup (Step 3)
                            └── AWS Secrets (Step 4)
```

### Service Dependencies

```
Ansible + Runner (Step 6)
    └── FreeIPA (Step 7)     ← All services depend on FreeIPA for DNS/auth
            ├── Vault (Step 8)
            └── Kubernetes (Step 9)
                    └── Nginx (Step 11)  ← Reverse proxy for K8s services
```

---

## Reference Documents (Non-Sequential)

These documents provide reference information, not deployment steps:

| Document | Purpose |
|----------|---------|
| [capacity-planning.md](capacity-planning.md) | Resource allocation for VMs/LXCs |

---

## Environment Summary

| Environment | Proxmox IP | Service VLANs | AWS Region |
|-------------|------------|---------------|------------|
| Dev | 10.0.5.110 | 60-65 | us-east-1 |
| Prod | 10.0.5.100 | 50-55 | eu-west-2 |

---

## Key IPs Quick Reference

### Shared Infrastructure
| Component | IP |
|-----------|-----|
| MikroTik Router | 10.0.5.1 |
| TP-Link AP | 10.0.5.10 |
| NAS (Management) | 10.0.5.120 |
| NAS (Storage) | 10.0.40.120 |

### Dev Environment (VLANs 60-65)
| Component | IP |
|-----------|-----|
| FreeIPA | 10.0.60.10 |
| K8s Masters | 10.0.61.10-12 |
| K8s API VIP | 10.0.61.100 |
| Vault Cluster | 10.0.62.10-12 |
| Vault VIP | 10.0.62.100 |
| Ansible | 10.0.63.10 |
| Local Runner | 10.0.63.20 |
| K8s Workers | 10.0.64.10-12 |
| NGINX | 10.0.65.10 |

### Prod Environment (VLANs 50-55)
| Component | IP |
|-----------|-----|
| FreeIPA | 10.0.50.10 |
| K8s Masters | 10.0.51.10-12 |
| K8s API VIP | 10.0.51.100 |
| Vault Cluster | 10.0.52.10-12 |
| Vault VIP | 10.0.52.100 |
| Ansible | 10.0.53.10 |
| Local Runner | 10.0.53.20 |
| K8s Workers | 10.0.54.10-12 |
| NGINX | 10.0.55.10 |

---

## Troubleshooting

All troubleshooting documentation is in the `troubleshooting/` folder, organized by technology:

| Folder | Topics |
|--------|--------|
| troubleshooting/network/ | VPN, VLAN, switch, router issues |
| troubleshooting/proxmox/ | Hypervisor, storage, backup issues |
| troubleshooting/identity/ | FreeIPA, Kerberos, LDAP issues |
| troubleshooting/github-actions/ | Workflow, runner issues |
| troubleshooting/aws/ | IAM, secrets, OIDC issues |
| troubleshooting/kubernetes/ | K8s cluster issues |
| troubleshooting/nginx/ | Reverse proxy, upstream, logging issues |
| troubleshooting/linux/ | General Linux issues |

---

## Re-Deployment Notes

For full environment rebuild:
1. Follow guides in sequence above
2. Each guide has verification steps - complete them before moving on
3. Golden templates (VM/LXC) auto-lock after creation
4. Workflow locks default to "true" (locked) for safety
5. Generate fresh GitHub runner tokens before runner setup (expires ~1 hour)

---
