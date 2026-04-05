# Troubleshooting Guide

This directory contains documented troubleshooting cases from real incidents in the hybrid-cloud-infrastructure environment.

## Case Index

| ID | Title | Components | Date |
|----|-------|------------|------|
| [TS-001](ts-001-flux-kustomization-dependency.md) | Flux Kustomization CRD Dependency Failure | Flux, ServiceMonitor, kube-prometheus-stack | 2026-04-05 |
| [TS-002](ts-002-k8s-master-resource-exhaustion.md) | Kubernetes Master Node Resource Exhaustion | kubelet, containerd, etcd, NFS | 2026-04-05 |
| [TS-003](ts-003-vault-service-account-authorization.md) | Vault Kubernetes Auth - Service Account Not Authorized | Vault, Kubernetes Auth, Helm | 2026-04-05 |

## Quick Reference

### Flux Issues
- CRD not found errors → Check deployment order, use `dependsOn` ([TS-001](ts-001-flux-kustomization-dependency.md))

### Node Issues
- kubectl hangs → Check node memory with `free -h` ([TS-002](ts-002-k8s-master-resource-exhaustion.md))
- Container runtime down → `systemctl restart containerd` ([TS-002](ts-002-k8s-master-resource-exhaustion.md))

### Vault Issues
- Pod stuck in Init → Check `vault-agent-init` logs ([TS-003](ts-003-vault-service-account-authorization.md))
- "service account name not authorized" → Verify SA name matches Vault role ([TS-003](ts-003-vault-service-account-authorization.md))

## Contributing
When documenting a new troubleshooting case:
1. Use the next available TS-XXX number
2. Include: Problem Summary, Symptoms, Root Cause, Investigation Steps, Solution, Verification, Prevention
3. Add evidence from actual commands and outputs
4. Update this README with the new case
