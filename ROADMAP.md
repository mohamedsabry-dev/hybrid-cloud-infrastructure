# Roadmap

---

## Where We Are

The infrastructure is functionally complete. It provisions, configures, monitors, alerts, and heals itself. The DR test phase validated resilience across storage, identity, ingress, compute, and quorum failures. Consolidation documented the decisions and signal flows so the system is readable.

---

## What's Next

- Custom PromQL dashboards and LogQL queries — own the observability stack at the query level, not just the deployment level
- Least-privilege RBAC design + NetworkPolicy namespace isolation + Calico CNI internals
- Rewrite the remediation scripts in clean Python — own every line
- Lambda + API path for master node recovery (when the k8s API is down, the remediation pod can't act — need an out-of-cluster recovery path through AWS)
- CloudWatch integration for Proxmox host-level metrics — visibility that survives cluster-level failures
- Node-level firewall rules and LXC network isolation — move from architecturally isolated to genuinely hardened
- CKA certification — target before end of September
- Next DR iteration: intentional control plane component failures (API server, controller manager, scheduler, etcd leader loss)

---

## GitOps Workflow

Feature branch pattern established after the April 18th incident:

```
feature/whatever branch
  └─► work freely, commit freely
        └─► Flux watches this branch → reconciles WIP immediately
              └─► iterate, test, stabilize
                    └─► squash merge to dev (1 clean commit)
                          └─► Flux already in sync — no reconcile needed
                                └─► public GitHub shows clean history
```

---

## The Stadium Stays Open

The infrastructure was designed as a stadium — ready to host any workload without infrastructure changes. Terraform for the VM, Ansible for domain join, existing VLANs for placement, existing Vault for secrets. Nothing about the foundation needs to change to add new workloads.

*Last updated: April 2026*