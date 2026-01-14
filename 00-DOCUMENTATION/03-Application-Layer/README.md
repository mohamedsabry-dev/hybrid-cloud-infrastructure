# Application Layer Documentation

> **Workload layer for containerized applications and Kubernetes cluster**

## Overview

This layer documents application workloads, Kubernetes cluster configuration, CI/CD pipelines, and container orchestration. Applications consume services from the platform layer and resources from the infrastructure layer.

---

## Documents in This Layer

### Planned
- Kubernetes Cluster Setup - Control plane and worker nodes
- K8s Networking - CNI, ingress, service mesh
- K8s Storage - Persistent volumes, storage classes
- Application Deployments - Helm charts, manifests
- CI/CD Pipelines - Jenkins, GitLab, automation
- Container Registry - Harbor, registry configuration
- Application Monitoring - APM, metrics, traces
- Service Catalog - Available applications and services

---

## Layer Responsibilities

**What belongs here:**
- Kubernetes cluster configuration (kubeadm, kubelet, etc.)
- Container orchestration (deployments, services, ingresses)
- Application workloads (microservices, web apps)
- CI/CD pipelines and automation
- Container images and registries
- Application-level monitoring and logging

**What does NOT belong here:**
- Platform services (IPA, Vault) → `02-Platform-Layer`
- Infrastructure (VMs, networking) → `01-Infrastructure-Layer`
- Cloud-native services → `04-Cloud-Layer`

---

## Application Architecture

```
┌─────────────────────────────────────────────────┐
│ Application Workloads                           │
│  ├─ Web Applications                            │
│  ├─ Microservices                               │
│  ├─ Databases (containerized)                   │
│  ├─ Message Queues                              │
│  └─ Batch Jobs                                  │
├─────────────────────────────────────────────────┤
│ Kubernetes Cluster                              │
│  ├─ Control Plane (kube-apiserver, etc.)        │
│  ├─ Worker Nodes                                │
│  ├─ CNI (Networking)                            │
│  ├─ CSI (Storage)                               │
│  └─ Ingress Controllers                         │
├─────────────────────────────────────────────────┤
│ Platform Services (IPA, Vault, Monitoring)      │
├─────────────────────────────────────────────────┤
│ Infrastructure (ESXi, Network, Storage)         │
└─────────────────────────────────────────────────┘
```

---

## Kubernetes Cluster Details

**Current Status:** Planning phase

**Planned Configuration:**
- Control Plane: 1 master node (k8s-master.home.lab)
- Worker Nodes: 3 workers (k8s-worker1/2/3.home.lab)
- CNI: TBD (Calico, Cilium, or Flannel)
- Ingress: TBD (NGINX, Traefik, or HAProxy)
- Storage: TBD (NFS, Longhorn, or Rook/Ceph)

---

## Integration with Platform Services

**Identity & Access:**
- K8s authentication via FreeIPA (OIDC/LDAP)
- Service accounts for automation
- RBAC policies tied to IPA groups

**Secrets Management:**
- Vault integration for application secrets
- External Secrets Operator
- Dynamic credentials for databases

**Backup & DR:**
- Velero for K8s cluster backup
- Application data backup via Veeam
- GitOps for configuration backup

**Monitoring & Logging:**
- Prometheus for metrics collection
- Grafana for visualization
- Loki/ELK for log aggregation

---

## Quick Links

- [Platform Layer (Services)](../02-Platform-Layer/)
- [Infrastructure Layer](../01-Infrastructure-Layer/)
- [Cloud Layer](../04-Cloud-Layer/)
- [Project Overview](../PROJECT-OVERVIEW.md)
