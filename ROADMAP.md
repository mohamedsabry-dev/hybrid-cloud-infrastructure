# Roadmap

---

## Where We Are

The infrastructure is functionally complete and production-grade. It provisions, configures, monitors, alerts, and heals itself. The DR test phase validated resilience across storage, identity, ingress, compute, and quorum failure scenarios. The consolidation phase documented the decisions, the incidents, and the signal flows that make the system understandable to someone who was not in the room when it was built.

The next phase is not about adding more — it is about going deeper on what already exists, expanding thoughtfully where it makes sense, and building the skills that the platform has been preparing for.

---

## Deeper Ownership — Python and Automation

The remediation system works. But working and owned are different things. The next step is to read, understand, and improve the Python script that drives the self-healing logic — not because it is broken, but because a system you cannot explain fully is a system you cannot trust fully.

This means understanding every decision in the script, improving the VMID overwrite protection using Proxmox task verification rather than external locking, and extending the self-healing path to cover master node failures through a node-level detection mechanism that does not depend on the Kubernetes API server being available.

Alongside this, Python scripting as a general skill needs dedicated practice — not tutorials, but real problems solved in the context of the existing infrastructure.

---

## Monitoring Stack — From Deployed to Understood

Prometheus, Grafana, Loki, and Alertmanager are running and alerting. The next step is owning them at the query level — writing PromQL for custom cluster health metrics, building Grafana dashboards that tell a story rather than just displaying numbers, tuning Alertmanager rules to reduce noise and improve signal, and learning LogQL well enough to investigate incidents through Loki without relying on kubectl logs.

Observability is only useful when you can ask it questions and trust the answers. That level of ownership is the goal.

---

## AWS Integration — Lambda and CloudWatch

The current self-healing architecture handles worker node failures through the remediation pod. The gap is master node failures — when the Kubernetes API server is unavailable, the remediation pod cannot act. The planned solution is a node-level detection mechanism on surviving workers that calls AWS API Gateway, which triggers a Lambda function holding Proxmox credentials, which restarts or restores the failed master VMs.

CloudWatch integration for Proxmox host-level monitoring — CPU, memory, IO — adds a layer of visibility that sits outside the Kubernetes cluster and therefore survives cluster-level failures. SNS notification chains from CloudWatch complete the alerting coverage for the most severe failure scenarios.

---

## Network Hardening

The network architecture is solid — 14 VLANs, WireGuard tunnels, MikroTik routing. The gap is enforcement at the node level. The next step is reviewing and tightening firewall rules at the MikroTik level, adding node-level firewall rules on workers and masters, closing unnecessary ports, and documenting the security posture properly. This is not urgent but it is the difference between an infrastructure that is architecturally isolated and one that is genuinely hardened.

---

## EKS — Managed Kubernetes as a Learning Environment

Adding EKS as a second Kubernetes environment serves a specific learning goal — understanding the differences between self-managed kubeadm clusters and managed Kubernetes at the control plane level. The comparison between managing your own etcd, API server, and scheduler versus having AWS manage them is a gap in understanding that EKS would close directly.

The cost consideration is real and EKS will be kept minimal — enough to learn from, not enough to run production workloads. Connecting EKS to the on-premises environment over WireGuard and running a workload that spans both clusters is the interesting experiment. Whether this stays long-term depends on what it teaches and what it costs.

---

## CKA Certification

The CKA exam is already being prepared for as a side effect of the consolidation and DR testing work. The formal preparation phase — timed practice exams, focused review of weak areas, speed optimization — needs to happen before the voucher expires in October. The target is to sit the exam before end of September, which gives enough time for a retake if needed.

The homelab is an advantage here. The exam is hands-on on a live cluster. Every DR test, every incident, every kubectl command run under pressure in this environment is exam preparation.

---

## Disaster Recovery — Continued Expansion

The current DR test coverage is solid but not complete. The remaining scenarios — master quorum failure with remediation recovery, full electricity simulation with measured RTO, and two-worker failure with priority-based preemption validation — are in the test plan and will be executed and documented. Each completed scenario either validates the design or reveals a gap worth fixing. Both outcomes are useful.

---

## Clean Flow:

As menitoend in TS before, the adoption of following with feature branches wul bethe core after publish >> So we need to make flux watch both dev + 1 fetutr branch "changable" so we keep work and commit free on it, and after stabilize and test, jsut squash it to dev >> Merge to Prod
feature/whatever branch
  └─► you work here freely
        └─► Flux watches this → reconciles your WIP immediately
              └─► 10 commits, fixes, iterations, testing
                    └─► environment stable and validated
                          └─► squash merge to dev (1 clean commit)
                                └─► Flux already in sync — no reconcile needed
                                      └─► public GitHub shows 1 clean commit
                                            └─► dev branch history stays professional


## The Stadium Stays Open

The infrastructure was designed as a stadium — ready to host any workload without infrastructure changes. New tools follow the same provisioning pattern: Terraform for the VM or LXC, Ansible for domain join and base configuration, existing VLANs for network placement, existing Vault for secrets. Nothing about the foundation needs to change to add new workloads.

This design decision means the platform continues to be useful as a learning environment long after the initial build phase is complete — for new tools, new integrations, new experiments, and new failures worth documenting.

*Last updated: April 2026*