# Task 2: Kill Network

**Trigger:** Break network paths at various levels.
**Baseline:** WordPress browsing + video upload running throughout all scenarios.

---

### Scenario 2.1 — External NGINX Down
Stop nginx service on ex-nginx (10.0.65.10).
Expected: app unreachable externally (confirmed SPOF).
Recover nginx → verify app accessible again. Measure downtime.
→ Run checklist.

### Scenario 2.2 — External NGINX Recovery via Proxmox
Test recovery path: Proxmox API → soft reboot → if fail → reset → if fail → force stop + restore from backup + start.
→ Run checklist.

### Scenario 2.3 — Kill 1 of 3 Ingress NGINX Pods
Kill 1 ingress-nginx pod.
Expected: app still reachable via remaining 2 pods.
→ Run checklist.

### Scenario 2.4 — Kill 2 of 3 Ingress NGINX Pods
Expected: app still reachable via remaining 1 pod.
→ Run checklist.

### Scenario 2.5 — Kill 3 of 3 Ingress NGINX Pods
Expected: app down. Recovery via Flux reconciliation.
Measure: time until Flux restores all 3 pods.
→ Run checklist.

### Scenario 2.6 — Ingress During Worker Node Failure
Kill a worker node hosting an ingress-nginx pod.
Verify: pod reschedules to another node. Anti-affinity + priority class working.
→ Run checklist.

### Scenario 2.7 — Calico CNI Failure
Stop calico-node daemonset pods.
Check: pod-to-pod communication across nodes.
→ Run checklist.

### Scenario 2.8 — CoreDNS Failure
Stop coredns pods.
Check: service discovery inside cluster (can pods resolve service names?).
→ Run checklist.

### Scenario 2.9 — Cross-Node Network Partition
Simulate network partition between 2 worker nodes.
Check: pods on isolated node, scheduling behavior, split-brain risk.
→ Run checklist.

### Scenario 2.10 — VLAN / Proxmox Network Drop
Drop network between Proxmox and router on SVC or storage level VLAN.
Trigger email notification via mgmt path.
→ Run checklist.

### Scenario 2.11 — Load Balancer Backend Loss
Kill 1 backend worker → check least_conn behavior on ex-nginx.
Verify: traffic shifts to remaining workers without errors.
→ Run checklist.

---

### Observation Checklist (run after every scenario):
- [ ] WordPress accessible externally
- [ ] Pod-to-pod communication working
- [ ] DNS resolution inside cluster (service names resolve)
- [ ] Ingress routing to correct backends
- [ ] Flux reconciliation of ingress controller
- [ ] Grafana: network traffic patterns
- [ ] Email notification received via mgmt path
- [ ] ex-nginx upstream health status