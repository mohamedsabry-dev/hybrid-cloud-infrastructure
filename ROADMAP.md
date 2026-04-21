# Roadmap

---

## Where We Are

The infrastructure is functionally complete and production-grade. It provisions, configures, monitors, alerts, and heals itself. The DR test phase validated resilience across storage, identity, ingress, compute, and quorum failure scenarios. The consolidation phase documented the decisions, the incidents, and the signal flows that make the system understandable to someone who was not in the room when it was built.

The next phase is not about adding more — it is about going deeper on what already exists, expanding thoughtfully where it makes sense, and building the skills that the platform has been preparing for.

---

## Phase 2

### 1. Observability Stack — From Deployed to Understood

Prometheus, Grafana, Loki, and Alertmanager are running and alerting. The next step is owning them at the query level — writing PromQL for custom cluster health metrics, building Grafana dashboards that tell a story rather than just displaying numbers, tuning Alertmanager rules to reduce noise and improve signal, and learning LogQL well enough to investigate incidents through Loki without relying on kubectl logs.

Observability is only useful when you can ask it questions and trust the answers. That level of ownership is the goal.

### 2. Kubernetes RBAC + Networking + CNI

Least-privilege RBAC design is a gap worth closing — understanding ClusterRole versus Role, designing service account permissions from first principles, and being able to audit what a given identity can and cannot do in the cluster. NetworkPolicy for namespace isolation, traffic restriction between workloads, and DNS-aware policy rules. Calico CNI internals — understanding what happens at the network layer when a pod communicates across nodes, not just that it works.

These are interview staples and real operational skills. The goal is to go deep, not wide.

### 3. Python — Own the Automation Layer

The remediation system works but it was not written from scratch and it is not fully owned. The next step is reading every line, understanding every decision, and rewriting it independently as the core learning exercise. Beyond remediation, Python scripting for Kubernetes API calls and Proxmox API calls specifically — the operations that Bash cannot handle cleanly. This is not a Python course. It is learning Python in the context of problems the infrastructure already has.

### 4. AWS Integration — Lambda and CloudWatch

The current self-healing architecture handles worker node failures through the remediation pod. The gap is master node failures — when the Kubernetes API server is unavailable, the remediation pod cannot act. The planned solution is a node-level detection mechanism on surviving workers that calls AWS API Gateway, which triggers a Lambda function holding Proxmox credentials, which restarts or restores the failed master VMs.

CloudWatch integration for Proxmox host-level monitoring — CPU, memory, IO — adds a layer of visibility that sits outside the Kubernetes cluster and therefore survives cluster-level failures. SNS notification chains from CloudWatch complete the alerting coverage for the most severe failure scenarios.

### 5. VM and LXC Hardening

The network architecture is solid — 14 VLANs, WireGuard tunnels, MikroTik routing. The gap is enforcement at the node level. Firewall rules on workers and masters, port closure, network isolation between LXC containers, and a documented security posture per machine type. This is not urgent but it is the difference between an infrastructure that is architecturally isolated and one that is genuinely hardened.

---

## Ongoing — Throughout Phase 2

### CKA Certification

The CKA exam is already being prepared for as a side effect of the consolidation and DR testing work. The formal preparation phase — timed practice exams, focused review of weak areas, speed optimization — needs to happen before the voucher expires in October. The target is to sit the exam before end of September, which gives enough time for a retake if needed.

The homelab is an advantage here. The exam is hands-on on a live cluster. Every DR test, every incident, every kubectl command run under pressure in this environment is exam preparation.

### Disaster Recovery — Intentional Failure Iterations

DR testing does not stop after the initial test phase. The next layer is intentional component-level failure — crashing the API server deliberately, taking down the controller manager, killing the scheduler, simulating etcd leader loss — and recording exactly what happens at each layer. The goal is not just recovery but understanding what the cluster does in the seconds and minutes between failure and recovery. These findings become incident documentation and interview material simultaneously.

Each iteration either validates the design or reveals a gap worth fixing. Both outcomes are useful.

---

## GitOps Workflow — Feature Branch Approach

As established after the April 18th incident, the workflow going forward follows a feature branch pattern:

```
feature/whatever branch
  └─► work freely, commit freely
        └─► Flux watches this branch → reconciles WIP immediately
              └─► iterate, test, stabilize
                    └─► squash merge to dev (1 clean commit)
                          └─► Flux already in sync — no reconcile needed
                                └─► public GitHub shows clean history
                                      └─► dev branch stays professional
```

Flux watches both dev and the active feature branch. When feature work is complete and squash-merged, Flux switches back to dev. This keeps the public repo clean while allowing free iteration internally.

---

## The Stadium Stays Open

The infrastructure was designed as a stadium — ready to host any workload without infrastructure changes. New tools follow the same provisioning pattern: Terraform for the VM or LXC, Ansible for domain join and base configuration, existing VLANs for network placement, existing Vault for secrets. Nothing about the foundation needs to change to add new workloads.

This design decision means the platform continues to be useful as a learning environment long after the initial build phase is complete — for new tools, new integrations, new experiments, and new failures worth documenting.

*Last updated: April 2026*