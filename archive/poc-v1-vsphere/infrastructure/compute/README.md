# Compute Resources

> **Resource allocation and capacity planning for 64GB RAM and 16 vCPU**

---

## Overview

This section documents the resource allocation strategy for the entire DC-K8s environment, including memory distribution, CPU over-commitment, and key architectural decisions that enable running a complete enterprise infrastructure on a single laptop.

**Total Capacity:**
- Memory: 64GB Physical RAM
- CPU: 16 vCPU @ 3.1GHz+
- VMs: 15 running simultaneously

---

## Documents in This Section

### [01-Resource-Overview.md](01-Resource-Overview.md)
Memory, CPU, and storage allocation strategy
- Memory allocation hierarchy (64GB breakdown)
- CPU over-commitment strategy (194% safe zone)
- Storage allocation summary

### [02-VM-Specifications-and-Decisions.md](02-VM-Specifications-and-Decisions.md)
Detailed VM specifications and architectural decisions
- Infrastructure layer VMs (vCenter, NAS, Veeam, pfSense)
- Production VMs (K8s, Vault, IPA, Ansible, Jenkins)
- Key architectural decisions (Cold standby DR, dedicated VMs)

### [03-Best-Practices-and-Optimization.md](03-Best-Practices-and-Optimization.md)
Resource optimization and best practices
- Memory management best practices
- CPU over-commitment guidelines
- Windows host stability considerations
- Future capacity planning

---

## Quick Reference

### Resource Summary

| Resource | Total | Infrastructure | Production | Buffer |
|----------|-------|----------------|------------|---------|
| **Memory** | 64GB | 23GB | 29GB | 12GB (host + overhead + buffer) |
| **CPU** | 16 vCPU | 11 vCPU | 10 vCPU | 194% over-commit (safe) |
| **VMs** | 15 total | 4 infra | 11 production | All running |

### Key Design Principles

✅ **Cold standby DR** instead of active HA (saves 29GB)
✅ **CPU over-commitment** at 194% (safe with complementary workloads)
✅ **Memory buffer** of 1GB for unexpected spikes
✅ **Three K8s workers** for true application-layer HA
✅ **Dedicated VMs** for critical services (Vault, Jenkins)

---

## Related Documentation

- [Storage Architecture](../Storage/)
- [Network Architecture](../Network/)
- [Infrastructure Layer Overview](../README.md)
- [Platform Layer](../../02-Platform-Layer/)
