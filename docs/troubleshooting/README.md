# Troubleshooting Guide

All troubleshooting documentation has been moved to the main troubleshooting directory, organized by component.

## Location

```
/troubleshooting/
├── kubernetes/    # Kubernetes, Flux, NFS, networking issues
├── vault/         # Vault cluster, auth, certificates
├── terraform/     # Terraform, Proxmox provider issues
├── proxmox/       # Proxmox host, backup, LXC/VM issues
├── identity/      # FreeIPA, Kerberos, LDAP issues
├── github/        # Git, GitHub issues
├── github-actions/# CI/CD pipeline issues
├── network/       # Network, firewall, DNS issues
├── linux/         # Linux OS issues
├── macos/         # macOS issues
├── aws/           # AWS cloud issues
└── security/      # Security related issues
```

## Recent Cases (Now Relocated)

| Old ID | New Location | Title |
|--------|--------------|-------|
| TS-001 | [kubernetes/10](../../troubleshooting/kubernetes/10-flux-kustomization-crd-dependency-failure.md) | Flux Kustomization CRD Dependency Failure |
| TS-002 | [kubernetes/11](../../troubleshooting/kubernetes/11-k8s-master-node-resource-exhaustion.md) | Kubernetes Master Node Resource Exhaustion |
| TS-003 | [kubernetes/12](../../troubleshooting/kubernetes/12-vault-k8s-auth-service-account-not-authorized.md) | Vault Kubernetes Auth - Service Account Not Authorized |

## Contributing

When documenting a new troubleshooting case:
1. Add to the appropriate component folder under `/troubleshooting/`
2. Use the next available number in that folder
3. Naming format: `{number}-{short-description}.md`
4. Include: Problem Summary, Symptoms, Root Cause, Investigation Steps, Solution, Verification, Prevention
