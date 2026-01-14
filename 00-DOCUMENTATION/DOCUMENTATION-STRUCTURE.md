# Documentation Structure Guide

> **Complete navigation guide for DC-K8s documentation organized by architectural layers**

---

## 📚 **Documentation Organization**

This documentation follows a **layered architecture** approach, mirroring the actual infrastructure design:

```
┌──────────────────────────────────────────────┐
│  04-Cloud-Layer/                             │  ← Hybrid cloud integration
│   Backup replication, DR to cloud            │
├──────────────────────────────────────────────┤
│  03-Application-Layer/                       │  ← Workloads & K8s
│   Kubernetes cluster, applications, CI/CD    │
├──────────────────────────────────────────────┤
│  02-Platform-Layer/                          │  ← Shared services
│   Identity, Backup, Vault, Monitoring        │
├──────────────────────────────────────────────┤
│  01-Infrastructure-Layer/                    │  ← Foundation
│   Compute, Network, Storage, ESXi            │
└──────────────────────────────────────────────┘
```

---

## 🗂️ **Layer Breakdown**

### [01-Infrastructure-Layer/](01-Infrastructure-Layer/)
**Foundation: Compute, Network, Storage**

Physical and virtual infrastructure providing resources.

**Current Documents:**
- Prerequisites
- Resource Allocation
- Network Architecture
- Storage Architecture

**Future:** ESXi config, vSwitch design, resource pools

---

### [02-Platform-Layer/](02-Platform-Layer/)
**Services: Identity, Backup, Security, Monitoring**

Shared services consumed by applications.

**Current Documents:**
- Identity Management (FreeIPA)
- Backup and DR Strategy
- DR Automation Scripts

**Future:** Vault, Veeam config, monitoring, logging, DNS/NTP

---

### [03-Application-Layer/](03-Application-Layer/)
**Workloads: Kubernetes, Applications, CI/CD**

Application deployments and container orchestration.

**Planned Documents:**
- K8s Cluster Setup
- Application Deployments
- CI/CD Pipelines
- Container Registry

---

### [04-Cloud-Layer/](04-Cloud-Layer/)
**Hybrid Cloud: Backup Replication, DR, Cloud Services**

Integration with AWS/Azure/GCP for backup, DR, and services.

**Planned Documents:**
- Cloud Backup Replication
- Disaster Recovery to Cloud
- Hybrid Connectivity (VPN)
- Cloud Cost Management

---

## 📖 **Root-Level Documents**

**[PROJECT-OVERVIEW.md](PROJECT-OVERVIEW.md)**
- High-level architecture overview
- Project goals and design philosophy
- Cross-layer architecture diagrams

**[README.md](README.md)**
- Quick start guide
- Navigation to key documents

**[DOCUMENTATION-STRUCTURE.md](DOCUMENTATION-STRUCTURE.md)** (this file)
- Complete documentation organization guide
- Navigation across all layers

---

## 🔍 **Quick Navigation by Topic**

### Identity & Access
- [FreeIPA Identity Management](02-Platform-Layer/) (Platform Layer)
- User accounts, groups, HBAC, sudo rules

### Network
- [Network Architecture](01-Infrastructure-Layer/) (Infrastructure Layer)
- IP addressing, VLANs, routing, pfSense

### Storage
- [Storage Architecture](01-Infrastructure-Layer/) (Infrastructure Layer)
- NAS, datastores, performance tuning

### Backup & DR
- [Backup Strategy](02-Platform-Layer/) (Platform Layer)
- [DR Automation Guide](DR/Guide.md)
- Veeam configuration, emergency shutdown

### Kubernetes
- [Application Layer](03-Application-Layer/) (Future)
- K8s cluster, workloads, CI/CD

### Cloud Integration
- [Cloud Layer](04-Cloud-Layer/) (Future)
- AWS/Azure integration, hybrid connectivity

---

## 📝 **Document Naming Conventions**

**Layer READMEs:**
- Each layer has `README.md` explaining its scope and contents

**Technical Documents:**
- Numbered by creation order within layer (e.g., `01-Prerequisites.md`)
- Descriptive names in kebab-case

**Cross-Layer Documents:**
- Stored at root level (e.g., `PROJECT-OVERVIEW.md`)
- Referenced from relevant layer READMEs

---

## 🎯 **Finding the Right Layer**

**Ask yourself:**

**Is it about physical/virtual infrastructure?**
→ `01-Infrastructure-Layer/` (ESXi, networking, storage)

**Is it a service used BY applications?**
→ `02-Platform-Layer/` (IPA, Vault, Veeam, monitoring)

**Is it an application or workload?**
→ `03-Application-Layer/` (K8s, microservices, CI/CD)

**Does it involve cloud providers?**
→ `04-Cloud-Layer/` (AWS, Azure, hybrid connectivity)

---

## 🚀 **Recommended Reading Order**

**For New Team Members:**
1. [PROJECT-OVERVIEW.md](PROJECT-OVERVIEW.md) - Understand the big picture
2. [01-Infrastructure-Layer/](01-Infrastructure-Layer/) - Learn the foundation
3. [02-Platform-Layer/](02-Platform-Layer/) - Understand shared services
4. [03-Application-Layer/](03-Application-Layer/) - See how applications run
5. [04-Cloud-Layer/](04-Cloud-Layer/) - Explore cloud integration

**For Operations:**
1. [DR Automation Guide](DR/Guide.md) - Emergency procedures
2. [Backup Strategy](02-Platform-Layer/) - Backup/restore procedures
3. [Identity Management](02-Platform-Layer/) - User/access management

**For Development:**
1. [Application Layer](03-Application-Layer/) - K8s and deployments
2. [Platform Services](02-Platform-Layer/) - Available services (Vault, IPA)
3. [Network Architecture](01-Infrastructure-Layer/) - Network connectivity

---

## 🛠️ **Contributing to Documentation**

**Adding a new document:**
1. Identify the correct layer
2. Follow naming conventions
3. Add reference to layer's `README.md`
4. Cross-reference from related documents

**Updating existing documents:**
1. Update "Last Updated" date at bottom
2. Document changes in git commit message
3. Update cross-references if structure changes

---

## 📊 **Documentation Coverage**

| Layer | Status | Documents | Coverage |
|-------|--------|-----------|----------|
| Infrastructure | ✅ Active | 4 docs | ~80% |
| Platform | ✅ Active | 3 docs | ~60% |
| Application | 🔜 Planned | 0 docs | 0% |
| Cloud | 🔜 Planned | 0 docs | 0% |

**Next Priorities:**
1. Move existing docs to appropriate layers
2. Complete Platform Layer (Vault, Veeam details)
3. Start Application Layer (K8s cluster setup)
4. Plan Cloud Layer (AWS S3 backup replication)

---

**Last Updated:** January 2026
**Maintained By:** Infrastructure Team
