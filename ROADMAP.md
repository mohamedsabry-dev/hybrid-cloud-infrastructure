# Roadmap

The infrastructure is functionally complete — it provisions, configures, monitors, alerts, and heals itself. DR testing validated resilience across storage, identity, ingress, compute, and quorum failures.

## What's Next

- Custom PromQL dashboards and LogQL queries — own observability at the query level
- RBAC least-privilege + NetworkPolicy namespace isolation
- Lambda recovery path for master node failure (out-of-cluster, via AWS)
- CloudWatch integration for Proxmox host-level metrics
- Node-level firewalls and LXC network hardening
- Next DR iteration: control plane component failures (API server, scheduler, etcd leader)
- CKA certification — target September 2026
