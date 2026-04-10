# Task 3: Kill Storage

**Trigger:** Break NFS connectivity and NAS availability.
**Baseline:** WordPress browsing + video upload running throughout all scenarios.
**Prerequisite:** Task 0 (Backup & Restore) validated before running any scenario here.

---

### Scenario 3.1 — Stop NFS Server
Stop NFS service on the NAS. Do not power off NAS.
Check: pod state (hang vs crash), can pods recover when NFS comes back?
→ Run checklist.

### Scenario 3.2 — Full NAS Power Off
Power off entire NAS.
Check cascade: pods, etcd, Proxmox backup mount, IPA external disk.
Recover NAS → verify everything reconnects.
→ Run checklist.

### Scenario 3.3 — Disconnect 1 Worker from NFS
Break NFS connectivity on 1 worker while pods are idle (no active uploads).
Recover connection → check if pods resume or need restart.
→ Run checklist.

### Scenario 3.4 — Disconnect 2 Workers from NFS
Same as 3.3 but 2 of 3 workers.
→ Run checklist.

### Scenario 3.5 — Disconnect All Workers from NFS
All workers lose NFS. Check: automatic recovery or permanent hang?
→ Run checklist.

### Scenario 3.6 — Mid-Upload NFS Disconnect
Start video upload → identify which worker handles it → disconnect NFS on that worker.
Check: upload outcome, DB transaction state, can same file be re-uploaded.
→ Run checklist.

### Scenario 3.7 — NFS Mount Options Behavior
Verify current mount options (soft vs hard, timeo, retrans values).
With soft mount (timeo=30, retrans=3): does pod return error instead of hanging?
Compare: if hard mount was used, does pod hang forever?
→ Run checklist.

### Scenario 3.8 — Kill CSI Controller
Kill nfs-csi-controller pod → immediately try creating a new PVC.
Expected: PVC stays Pending until controller recovers.
→ Run checklist.

### Scenario 3.9 — Kill CSI Controller Mid-PVC Creation
Start PVC creation → kill nfs-csi-controller mid-way.
Check: does PVC get stuck permanently or resolve after controller restarts?
→ Run checklist.

### Scenario 3.10 — Kill CSI Node Pod (Existing Mounts)
Kill nfs-csi-node pod on a worker that has pods with active NFS mounts.
Check: do existing mounts survive? (They should — kernel handles mounts, not CSI pod.)
→ Run checklist.

### Scenario 3.11 — Kill CSI Node Pod (New Mount)
Kill nfs-csi-node pod on a worker → schedule a new pod with PVC to that same worker.
Check: does the new pod mount succeed, or stuck in ContainerCreating?
→ Run checklist.

### Scenario 3.12 — Delete CSI Node DaemonSet Entirely
Delete the whole nfs-csi-node daemonset.
Check: existing mounted volumes survive? New pods can mount?
→ Run checklist.

### Scenario 3.13 — Combined: NFS Server Down + CSI Controller Down
Both down at the same time. Recover one at a time.
Test: does recovery order matter? (NFS first then CSI, or CSI first then NFS?)
→ Run checklist.

### Scenario 3.14 — Delete PV While PVC Exists
Delete a PV that has a bound PVC.
Check: PVC state (Lost?), pod behavior, data accessibility.
→ Run checklist.

### Scenario 3.15 — Create PVC While NFS Unreachable
NFS server is down → try to create a new PVC via StorageClass.
Check: does it stay Pending or fail outright?
→ Run checklist.

### Scenario 3.16 — CSI Priority Class Verification
Verify nfs-csi-node pods have system-node-critical priority.
Force shutdown a worker → start it → monitor startup order.
Expected: CSI node pod starts before app pods.
→ Run checklist.

### Scenario 3.17 — CSI vs App Eviction Under Pressure
Create memory pressure on a worker.
Expected: app pods evicted, CSI node pod survives (system-node-critical).
→ Run checklist.

### Scenario 3.18 — CSI + App Pod Simultaneous Kill
Delete nfs-csi-node pod + app pod on the same worker at the same time.
Measure: time from CSI pod recovery → app pod mount retry → app pod Running.
→ Run checklist.

---

### Observation Checklist (run after every scenario):
- [ ] WordPress accessible
- [ ] Upload data persisted or lost
- [ ] DB transaction state (duplicate conflicts?)
- [ ] PVC/PV binding state
- [ ] CSI controller pod status
- [ ] CSI node pod status
- [ ] Pod mount events (FailedMount, retry count, backoff timing)
- [ ] NFS mount recovery (auto vs manual remount)
- [ ] IPA external disk state (NFS-dependent)
- [ ] Proxmox backup mount state (NFS-dependent)
- [ ] Grafana: storage I/O metrics