# Task 2: Kill Network

**Trigger:** Break network paths at various levels.
**Baseline:** WordPress browsing + video upload running throughout all scenarios.

---

### Scenario 2.1 — External NGINX Down
Stop external nginx (SPOF for external traffic).

- Action: Stop nginx service on ex-nginx (10.0.65.10)
- Check: App unreachable externally (confirmed SPOF)
- Check: ex-nginx upstream health status
- Check: least_conn behavior when backend workers change
- Recovery: Start nginx service
- Measure: Downtime duration
- Check: App accessible again

→ Run checklist.

### Scenario 2.2 — External NGINX Recovery via Proxmox
Test recovery escalation path.

- Action: Soft reboot ex-nginx via Proxmox API
- Check: If soft reboot fails → reset
- Check: If reset fails → force stop + restore from backup + start
- Check: nginx serving traffic after recovery
- Check: Email notification sent

→ Run checklist.

### Scenario 2.3 — Kill 1 of 3 Ingress NGINX Pods
Partial ingress-nginx failure.

- Action: `kubectl delete pod -n ingress-nginx <one-pod>`
- Check: App still reachable via remaining 2 pods
- Check: Traffic distribution shifts to surviving pods
- Check: Killed pod restarts automatically

→ Run checklist.

### Scenario 2.4 — Kill 3 of 3 Ingress NGINX Pods
Full ingress-nginx failure.

- Action: `kubectl delete pod -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx`
- Check: App down (expected)
- Check: Flux reconciliation kicks in
- Measure: Time until Flux restores all 3 pods
- Check: App accessible after recovery

→ Run checklist.

### Scenario 2.5 — Calico CNI Failure
Stop CNI daemonset pods.

- Action: `kubectl delete pod -n calico-system -l k8s-app=calico-node`
- Check: Pod-to-pod communication across nodes
- Check: Existing connections survive? New connections fail?
- Check: Calico pods restart automatically
- Check: Network recovers after restart

→ Run checklist.

### Scenario 2.6 — CoreDNS Failure
Stop cluster DNS.

- Action: `kubectl delete pod -n kube-system -l k8s-app=kube-dns`
- Check: Service discovery inside cluster broken
- Check: Pods cannot resolve service names
- Check: Pods using IP directly still work?
- Check: CoreDNS pods restart automatically
- Check: DNS resolution recovers

→ Run checklist.

### Scenario 2.7 — VLAN / Proxmox Network Drop
Drop network between Proxmox and router.

- Action: Drop SVC or storage level VLAN
- Check: Impact on VMs and LXCs
- Check: Impact on NFS mounts
- Check: Impact on external access
- Check: Email notification sent via mgmt path (separate VLAN)

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
