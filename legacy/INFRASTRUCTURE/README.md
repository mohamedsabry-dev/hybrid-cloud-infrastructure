# Infrastructure Layer Documentation

> **Foundation layer providing compute, network, and storage resources**

## Overview

This layer documents the physical and virtual infrastructure that forms the foundation of the DC-K8s environment. It includes hardware specifications, hypervisor configuration, network topology, and storage architecture.

---

## Documents in This Layer

### Current
- (Move here) `../01-Prerequisites.md` - Hardware and software requirements
- [Compute Resources](Compute/) - Resource allocation and capacity planning
- [Network Architecture](Network/) - Three-tier network design with security segmentation
- [Storage Architecture](Storage/) - Multi-tier storage design with NFS centralization

### Planned
- ESXi configuration and networking
- vSwitch and port group design
- Physical network topology
- Resource pools and DRS configuration

---

## Layer Responsibilities

**What belongs here:**
- Hypervisor (ESXi) configuration
- Network design (VLANs, subnets, routing)
- Storage design (datastores, NAS, performance)
- Compute resources (CPU, RAM allocation)
- Physical infrastructure prerequisites

**What does NOT belong here:**
- Platform services (IPA, Vault, Veeam) → `02-Platform-Layer`
- Applications (K8s, workloads) → `03-Application-Layer`
- Cloud integrations → `04-Cloud-Layer`

---

## Quick Links

- [Compute Resources](Compute/)
- [Network Architecture](Network/)
- [Storage Architecture](Storage/)
- [Platform Layer](../02-Platform-Layer/)
- [Project Overview](../PROJECT-OVERVIEW.md)
