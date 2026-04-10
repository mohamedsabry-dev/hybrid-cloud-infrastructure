# Task 1: Kill Compute

**Trigger:** Take down pods, workers, masters, vault nodes in various combinations.
**Baseline:** WordPress browsing + video upload running throughout all scenarios.

---

### Scenario 1.1 — Single Pod Kill
Kill 1 WordPress pod (restart, recreate, force delete). Repeat for: mariadb, vault-injector, ingress-nginx, flux, prometheus, exporters.
→ Run checklist.

### Scenario 1.2 — Partial Pod Scale Loss
Kill 2 of 3 pods for each component.
→ Run checklist.

### Scenario 1.3 — Full Pod Scale Loss
Kill 3 of 3 pods for each component.
→ Run checklist.

### Scenario 1.4 — Mid-Upload Pod Kill
Start video upload → identify which pod is serving via nginx → kill that pod mid-upload.
Check: does upload data persist? Can same file be re-uploaded or does DB hit duplicate name conflict?
→ Run checklist.

### Scenario 1.5 — Pod Eviction Under Pressure
Create memory/CPU pressure on a worker node. Observe which pods get evicted and which survive.
Document the priority order: CSI > ingress > flux > app > exporters (or whatever the actual order is).
→ Run checklist.

### Scenario 1.6 — Single Worker Node Down
Restart 1 worker node. Then repeat with force shutdown.
Measure: time from NotReady until pods reschedule to other workers.
→ Run checklist.

### Scenario 1.7 — Partial Worker Loss
2 of 3 workers down (force shutdown).
→ Run checklist.

### Scenario 1.8 — Full Worker Loss
3 of 3 workers down (force shutdown).
→ Run checklist.

### Scenario 1.9 — Mid-Upload Worker Kill
Start video upload → identify which worker node via nginx → force shutdown that worker mid-upload.
Check: upload data persistence, DB transaction state, can same file be re-uploaded.
→ Run checklist.

### Scenario 1.10 — Single Master Node Down
Restart 1 master. Then repeat with force shutdown.
Check: can kubectl commands still execute? Does etcd still have quorum?
→ Run checklist.

### Scenario 1.11 — Partial Master Loss
2 of 3 masters down (force shutdown).
Check: etcd quorum, API server, scheduler, controller-manager.
→ Run checklist.

### Scenario 1.12 — Full Master Loss
3 of 3 masters down. Total control plane loss.
Document: recovery sequence to bring cluster back.
→ Run checklist.

### Scenario 1.13 — Single Vault Node Down
Restart 1 vault pod. Then repeat with force shutdown.
→ Run checklist.

### Scenario 1.14 — Vault Quorum Loss
2 of 3 vault nodes down. Quorum lost.
Check: existing pods still serving with cached secrets? New pods can fetch secrets?
→ Run checklist.

### Scenario 1.15 — Full Vault Outage
3 of 3 vault nodes down. Full outage.
Same checks as 1.14.
→ Run checklist.

### Scenario 1.16 — Vault Seal/Unseal Cycle
Manually seal vault → verify auto-unseal triggers → verify app health after unseal.
Then: break auto-unseal (change/remove secrets) → manual recovery → verify.
→ Run checklist.

### Scenario 1.17 — Combined: 2 Workers + 1 Master
Force shutdown 2 workers + 1 master simultaneously.
→ Run checklist.

### Scenario 1.18 — Combined: 2 Workers + 2 Masters
Force shutdown 2 workers + 2 masters.
→ Run checklist.

### Scenario 1.19 — Combined: 3 Workers + 1 Master
All worker capacity gone, partial control plane.
→ Run checklist.

### Scenario 1.20 — Combined: 2 Workers + 3 Masters
Full control plane loss + partial worker loss.
→ Run checklist.

### Scenario 1.21 — Auto-Recovery via Proxmox API
Trigger after a node (master, worker, or vault) stays down for extended period:
1. Proxmox API → force stop the node
2. Copy node to different VMID/CTID (for log analysis later)
3. Restore latest backup of that node
4. Start the node
5. Verify it rejoins its cluster (K8s or Vault)
6. Verify app + etcd health
7. Confirm email notification sent
→ Run checklist.

---

### Observation Checklist (run after every scenario):
- [ ] WordPress accessible (browse + upload)
- [ ] DB integrity (no duplicate conflicts, no orphaned transactions)
- [ ] etcd health and leader election
- [ ] Flux reconciliation status
- [ ] Helm release state
- [ ] Vault sealed/unsealed status
- [ ] Pod scheduling and priority behavior
- [ ] Grafana: CPU, mem, pod restarts on remaining nodes
- [ ] Prometheus scraping targets reachable
- [ ] CrashLoopBackOff count and recovery timing