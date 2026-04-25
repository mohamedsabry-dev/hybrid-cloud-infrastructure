# Deployment Documentation

This folder contains setup guides for deploying the hybrid cloud infrastructure from scratch.

---

## Deployment Sequence

Follow these guides **in order**. Each step depends on the previous ones being complete.

| Order | Guide | Purpose |
|-------|-------|---------|
| 0 | [00-network-setup-guide.md](00-network-setup-guide.md) | Physical network (router, switch, AP) |
| 1 | [01-proxmox-setup-guide.md](01-proxmox-setup-guide.md) | Proxmox VE hypervisor installation |
| 2 | [02-aws-bootstrap-setup-guide.md](02-aws-bootstrap-setup-guide.md) | AWS OIDC, state bucket, IAM bootstrap |
| 3 | [03-github-setup-guide.md](03-github-setup-guide.md) | GitHub secrets, variables, runners |
| 4 | [04-aws-secrets-setup-guide.md](04-aws-secrets-setup-guide.md) | AWS Secrets Manager placeholders |
| 5 | [05-vpn-setup-guide.md](05-vpn-setup-guide.md) | WireGuard VPN to AWS |
| 6 | [06-ansible-runner-setup-guide.md](06-ansible-runner-setup-guide.md) | Ansible LXC + GitHub Runner LXC |
| 7 | [07-freeipa-setup-guide.md](07-freeipa-setup-guide.md) | FreeIPA identity management |
| 8 | [08-vault-setup-guide.md](08-vault-setup-guide.md) | HashiCorp Vault cluster |
| 9 | [09-k8s-setup-guide.md](09-k8s-setup-guide.md) | Kubernetes cluster |
| 10 | [10-k8s-flux-setup-guide.md](10-k8s-flux-setup-guide.md) | Flux bootstrap on K8s + app/infra loop pattern |
| 11 | [11-vault-k8s-integration-guide.md](11-vault-k8s-integration-guide.md) | Vault-Kubernetes trust + secret injection |
| 12 | [12-etcd-backup-integration-guide.md](12-etcd-backup-integration-guide.md) | etcd backup CronJob → Vault AWS Secrets Engine → S3 (temp STS creds, no long-lived keys in K8s) |
| 13 | [13-endpoint-dns-ingress-setup-guide.md](13-endpoint-dns-ingress-setup-guide.md) | Endpoint DNS + ingress-nginx controller + external Nginx reverse proxy |
| 14 | [14-remediation-integration-guide.md](14-remediation-integration-guide.md) | Remediation integration — Proxmox API + K8s + Alertmanager for worker self-healing |
| 15 | [15-monitoring-stack-setup-guide.md](15-monitoring-stack-setup-guide.md) | Grafana + Prometheus + Loki + Alertmanager monitoring stack |

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
                    └── Flux bootstrap (Step 10)        ← GitOps reconciles everything below
                            ├── Vault-K8s trust (Step 11)
                            ├── etcd-backup → Vault → S3 (Step 12)
                            ├── Endpoint DNS + ingress (Step 13)
                            └── Remediation (Step 14)   ← Worker self-healing via Proxmox API
```

---

## Reference Documents (Non-Sequential)

These documents provide reference information, not deployment steps:

| Document | Purpose |
|----------|---------|
| [../diagrams/](../diagrams/) | Architecture diagrams (draw.io) — 8 diagrams covering full stack |
| [../proxmox/capacity-planning.md](../proxmox/capacity-planning.md) | Resource allocation for VMs/LXCs (lives in the proxmox/ folder) |

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
| troubleshooting/github/ | Workflow, runner issues |
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
