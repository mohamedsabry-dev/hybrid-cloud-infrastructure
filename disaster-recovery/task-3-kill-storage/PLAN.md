# Task 3: Kill Storage

**Trigger:** Break NFS connectivity and NAS availability.
**Baseline:** WordPress browsing + video upload running throughout all scenarios.
**Prerequisite:** Task 0 (Backup & Restore) validated before running any scenario here.

---

### Scenario 3.1 — Stop NFS Server
Stop NFS service on the NAS (do not power off NAS).
- Action: Stop NFS daemon on NAS
- Check: Pod state — do they hang (hard mount) or return error (soft mount)?
- Check: Can pods recover automatically when NFS comes back?
- Check: Do pods need manual restart after NFS recovery?
→ Run checklist.

### Scenario 3.2 — Full NAS Power Off
Power off entire NAS device.
- Action: Shutdown NAS completely
- Check: WordPress pods behavior
- Check: Proxmox backup mount (NFS-based)
- Check: IPA external disk (NFS-based)
- Recovery: Power on NAS → verify all mounts reconnect
→ Run checklist.

### Scenario 3.3 — Disconnect 1 Worker from NFS
Break NFS connectivity on 1 worker node (no active uploads).
- Action: Block NFS traffic on worker (iptables or unplug VLAN)
- Check: Pods on that worker — hang or error?
- Check: Pods on other workers — still serving?
- Recovery: Restore connection → do pods resume or need restart?
→ Run checklist.

### Scenario 3.4 — Mid-Upload NFS Disconnect
Disconnect NFS while upload is in progress.
- Action: Start video upload to WordPress
- Action: Identify which worker handles it (check nginx logs)
- Action: Disconnect NFS on that worker mid-upload
- Check: Upload outcome — success, fail, or hang?
- Check: DB transaction state — committed or rolled back?
- Check: Can same file be re-uploaded? (duplicate name conflict?)
→ Run checklist.

### Scenario 3.5 — NFS Mount Options Behavior
Verify soft mount behavior vs hard mount.
- Action: Check current mount options (`mount | grep nfs`)
- Expected: `soft,timeo=30,retrans=3` (from previous fix)
- Test: With soft mount — does pod return error instead of hanging?
- Compare: What would happen with hard mount? (document, don't test)
→ Run checklist.

### Scenario 3.6 — Kill CSI Controller
Kill the CSI controller pod and test PVC provisioning.
- Action: `kubectl delete pod -n kube-system -l app=csi-nfs-controller`
- Action: Immediately create a new PVC
- Check: PVC stays Pending until controller recovers
- Check: Controller pod restarts automatically
- Check: PVC becomes Bound after controller recovery
→ Run checklist.

### Scenario 3.7 — Kill CSI Node Pod (Existing Mounts)
Kill CSI node pod on a worker with active NFS mounts.
- Action: Identify worker with WordPress pods
- Action: `kubectl delete pod -n kube-system -l app=csi-nfs-node` (on that node)
- Check: Existing mounts survive (kernel handles mounts, not CSI pod)
- Check: WordPress pods continue serving
- Check: CSI node pod restarts automatically
→ Run checklist.

### Scenario 3.8 — Combined: NFS Server Down + CSI Controller Down
Both NFS and CSI controller down simultaneously.
- Action: Stop NFS service on NAS
- Action: Kill CSI controller pod
- Recovery Option A: NFS first, then wait for CSI
- Recovery Option B: CSI first, then NFS
- Check: Does recovery order matter?
- Check: Do pods recover automatically or need intervention?
→ Run checklist.

### Scenario 3.9 — Delete PV While PVC Exists
Delete a PV that has a bound PVC (tests reclaim policy).
- Action: `kubectl delete pv <wordpress-pv>`
- Check: PVC state — does it show `Lost`?
- Check: Pod behavior — can it still access data?
- Check: What is the reclaim policy? (`Retain` vs `Delete`)
- Recovery: Recreate PV → does PVC rebind?
→ Run checklist.

### Scenario 3.10 — Create PVC While NFS Unreachable
Try to provision new storage while NFS is down.
- Action: Stop NFS service on NAS
- Action: Create new PVC via StorageClass
- Check: PVC state — Pending or Failed?
- Check: CSI controller logs — what error?
- Recovery: Start NFS → does PVC become Bound automatically?
→ Run checklist.

### Scenario 3.11 — Kill ALL CSI Controller Replicas (Full Controller Outage)
Kill all CSI controller replicas and verify existing workloads unaffected.
- Action: Check controller replicas: `kubectl get deploy -n kube-system csi-nfs-controller`
- Action: Scale to 0 OR delete all pods: `kubectl scale deploy csi-nfs-controller -n kube-system --replicas=0`
- Check: Existing pods still serving (mounts handled by kernel, not CSI)
- Check: WordPress browsing + uploads still work
- Check: New PVC creation stays Pending (no controller to provision)
- Check: PVC deletion waits (no controller to cleanup)
- Recovery: Scale back up: `kubectl scale deploy csi-nfs-controller -n kube-system --replicas=2`
- Check: Pending PVCs become Bound after controller recovery
→ Run checklist.

### Scenario 3.12 — Kill ALL CSI Node Pods (Full Node Driver Outage)
Kill all CSI node pods and verify existing mounts survive.
- Action: Check node pods: `kubectl get ds -n kube-system csi-nfs-node`
- Action: Delete all node pods: `kubectl delete pod -n kube-system -l app=csi-nfs-node`
- Check: Existing mounts survive (kernel NFS mounts independent of CSI)
- Check: Existing pods continue serving
- Check: New pod scheduling with PVC — can it mount? (expected: no, NodePublishVolume fails)
- Check: CSI node pods restart automatically (DaemonSet)
- Check: New pods can mount after node pods recover
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
- [ ] **Grafana:** storage I/O metrics, NFS latency, mount errors
- [ ] **Prometheus:** node-exporter filesystem metrics, CSI metrics
- [ ] **Loki:** CSI controller/node logs, kubelet mount errors, app I/O errors
