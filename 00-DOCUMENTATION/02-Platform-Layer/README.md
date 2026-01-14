# Platform Layer Documentation

> **Service layer providing identity, security, backup, and infrastructure services**

## Overview

This layer documents platform services that run on the infrastructure and provide capabilities to applications. These are shared services that multiple applications depend on.

---

## Documents in This Layer

### Current
- (Move here) `../05-Identity-Management-IPA.md` - FreeIPA domain, users, RBAC
- (Move here) `../06-Backup-and-DR-Strategy.md` - Backup strategy and policies
- (Move here) `../DR/` - Disaster recovery automation and procedures

### Planned
- HashiCorp Vault - Secrets management
- Veeam Backup - Detailed backup configuration
- Monitoring Platform - Prometheus, Grafana, alerting
- Logging Platform - ELK/Loki stack
- Certificate Management - SSL/TLS certificate automation
- DNS/DHCP Services - Internal DNS and DHCP
- NTP Configuration - Time synchronization hierarchy

---

## Layer Responsibilities

**What belongs here:**
- Identity and access management (FreeIPA, LDAP, Kerberos)
- Secrets management (HashiCorp Vault)
- Backup and disaster recovery (Veeam, backup automation)
- Monitoring and observability (metrics, logs, traces)
- Security services (firewalls, certificate management)
- Shared infrastructure services (DNS, NTP, SMTP)

**What does NOT belong here:**
- Infrastructure (networking, storage) → `01-Infrastructure-Layer`
- Applications (K8s workloads) → `03-Application-Layer`
- Cloud services → `04-Cloud-Layer`

---

## Platform Services Architecture

```
┌─────────────────────────────────────────────────┐
│ Applications (K8s, VMs)                         │
├─────────────────────────────────────────────────┤
│ Platform Services Layer                         │
│  ├─ Identity (FreeIPA)                          │
│  ├─ Secrets (Vault)                             │
│  ├─ Backup (Veeam)                              │
│  ├─ Monitoring (Prometheus/Grafana)             │
│  ├─ Logging (ELK/Loki)                          │
│  └─ Shared Services (DNS, NTP, SMTP)            │
├─────────────────────────────────────────────────┤
│ Infrastructure (Compute, Network, Storage)      │
└─────────────────────────────────────────────────┘
```

---

## Design Philosophy

**Why Platform Layer?**
- **Separation of Concerns:** Applications shouldn't manage their own identity/backup/monitoring
- **Reusability:** One IPA server serves all applications
- **Consistency:** Standardized monitoring, logging, backup across all workloads
- **Security:** Centralized secret management reduces credential sprawl

**Trade-offs Made:**
- Complexity: More components to manage vs. application-specific solutions
- Dependency: Applications depend on platform availability
- Benefit: Operational efficiency, standardization, reduced duplication

---

## Quick Links

- [Identity Management (IPA)](../05-Identity-Management-IPA.md)
- [Backup and DR Strategy](../06-Backup-and-DR-Strategy.md)
- [DR Automation Guide](../DR/Guide.md)
- [Infrastructure Layer](../01-Infrastructure-Layer/)
- [Application Layer](../03-Application-Layer/)
