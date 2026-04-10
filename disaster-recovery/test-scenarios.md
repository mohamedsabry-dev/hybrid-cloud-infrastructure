# Kubernetes & Vault Cluster — Chaos Engineering Test Plan v5

---

## How to Use This Plan

Each Task is a failure domain (Compute, Network, Storage, etc.).
Each Task contains numbered **Scenarios** that escalate in severity.
After every Scenario, run the **Observation Checklist** at the bottom of that Task.
Execute Task 0 (Backup & Restore) FIRST — it's your safety net before any destructive testing.

---


## Task 0: Backup & Restore Validation

**Priority:** Execute FIRST — before Tasks 1 through 5. This is your safety net.

### Scenario 0.1 — ETCD Backup & Restore (Normal)
Backup etcd snapshot under normal operation → restore → verify cluster state.
→ Run checklist.

### Scenario 0.2 — ETCD Backup & Restore (Under Load)
Backup etcd during active workload (uploads, deployments running) → restore → verify data integrity.
→ Run checklist.

### Scenario 0.3 — ETCD Snapshot Corruption
Simulate corrupted etcd snapshot → attempt restore → document failure behavior and recovery path.
→ Run checklist.

### Scenario 0.4 — Vault Raft Backup & Restore (Normal)
Backup Vault raft → restore → verify all secrets accessible.
→ Run checklist.

### Scenario 0.5 — Vault Raft Backup Integrity
Verify backup integrity before restore (checksum, validation).
Restore with different quorum states (1, 2, 3 nodes).
→ Run checklist.

### Scenario 0.6 — WordPress Data Backup & Restore
Backup WordPress uploads + MariaDB during active operations.
Restore → verify: uploads intact, DB consistent, no missing/duplicate records.
→ Run checklist.

### Scenario 0.7 — MariaDB Point-in-Time Recovery
Test point-in-time recovery for MariaDB.
Verify: can you restore to a specific moment before a failure?
→ Run checklist.

### Scenario 0.8 — Local Backup Without NFS
Backup to local storage (no NFS dependency).
Then: simulate NFS down → restore from local backup → verify.
Confirms you can recover even when NFS is unavailable.
→ Run checklist.

### Scenario 0.9 — Backup Copy Strategy
Backup to local → scheduled copy to NFS.
Verify: only latest backup kept on local, older copies on NFS.
Test: NFS goes down → local backup still usable.
→ Run checklist.

### Task 0 — Observation Checklist (run after every scenario):
- [ ] Backup completed successfully (under load if applicable)
- [ ] Restore produced consistent state
- [ ] DB integrity (no missing / duplicate records)
- [ ] WordPress uploads intact
- [ ] Vault secrets accessible after raft restore
- [ ] etcd cluster healthy after restore
- [ ] Local backup usable without NFS
- [ ] Backup copy to NFS succeeded

---


## Task 1: Kill Compute

**Baseline:** WordPress browsing + video upload running throughout all scenarios.

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

### Task 1 — Observation Checklist (run after every scenario):
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

---

## Task 2: Kill Network

**Baseline:** WordPress browsing + video upload running throughout all scenarios.

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

### Task 2 — Observation Checklist (run after every scenario):
- [ ] WordPress accessible externally
- [ ] Pod-to-pod communication working
- [ ] DNS resolution inside cluster (service names resolve)
- [ ] Ingress routing to correct backends
- [ ] Flux reconciliation of ingress controller
- [ ] Grafana: network traffic patterns
- [ ] Email notification received via mgmt path
- [ ] ex-nginx upstream health status

---

## Task 3: Kill Storage

**Baseline:** WordPress browsing + video upload running throughout all scenarios.
**Prerequisite:** Task 6 (Backup & Restore) validated before running any scenario here.

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

### Task 3 — Observation Checklist (run after every scenario):
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

---

## Task 4: Kill Vault

**Baseline:** WordPress browsing + video upload running throughout all scenarios.

### Scenario 4.1 — Single Vault Pod Restart
Restart 1 vault pod gracefully.
→ Run checklist.

### Scenario 4.2 — Single Vault Pod Force Kill
Force shutdown 1 vault pod.
→ Run checklist.

### Scenario 4.3 — Vault Quorum Loss (2 of 3 Down)
Kill 2 vault nodes. Quorum lost.
Check: existing pods with cached secrets still running? New pods can fetch secrets?
→ Run checklist.

### Scenario 4.4 — Full Vault Outage (3 of 3 Down)
Kill all 3 vault nodes.
Same checks as 4.3.
→ Run checklist.

### Scenario 4.5 — Manual Seal → Auto-Unseal
Manually seal vault → verify auto-unseal triggers correctly → verify app health.
→ Run checklist.

### Scenario 4.6 — Break Auto-Unseal
Remove or change the secrets used for auto-unseal.
Vault stays sealed → manual recovery procedure → verify app recovers.
→ Run checklist.

### Scenario 4.7 — Vault-Injector Behavior During Degraded Vault
Vault cluster degraded (1 or 2 nodes down).
Check: vault-injector sidecar behavior, can it still inject to new pods?
What if vault-injector itself is rescheduling?
→ Run checklist.

### Scenario 4.8 — Vault Raft Backup & Restore (Normal)
Backup Vault raft under normal operation → restore → verify all secrets intact.
→ Run checklist.

### Scenario 4.9 — Vault Raft Backup & Restore (Under Load)
Backup Vault raft during active workload → restore → verify integrity.
→ Run checklist.

### Scenario 4.10 — Vault Raft Restore with Partial Quorum
Restore raft backup with only 1 node available. Then 2 nodes. Then 3 nodes.
Document which quorum states allow successful restore.
→ Run checklist.

### Task 4 — Observation Checklist (run after every scenario):
- [ ] Existing pods still serving with cached secrets
- [ ] New pods can / cannot inject secrets
- [ ] Vault UI accessible
- [ ] Vault sealed / unsealed status
- [ ] vault-injector pod healthy and scheduling correctly
- [ ] App functionality (WordPress login, DB connections via Vault creds)
- [ ] Raft backup integrity after restore

---

## Task 5: Kill Power / Infrastructure

**Baseline:** Full environment running normally before each scenario.
**Prerequisite:** Task 6 (Backup & Restore) validated first.

### Scenario 5.1 — Graceful Power Down (UPS Triggered)
Simulate electricity loss → UPS triggers shutdown script.
Verify shutdown order executes correctly:
1. App pods
2. K8s workers
3. K8s masters
4. Vault
5. Proxmox
→ Run checklist.

### Scenario 5.2 — Graceful Power Down with NFS Dependency
Before Proxmox shutdown: umount NFS backup storage.
Verify: Proxmox shuts down cleanly without hanging on NFS mount.
After power up: remount NFS backup storage before starting VMs.
→ Run checklist.

### Scenario 5.3 — Full Recovery Boot Sequence
Power everything back on after graceful shutdown.
Verify boot order and all services come back:
NAS/NFS → Proxmox → IPA → Vault → K8s masters → K8s workers → App pods.
Check: IPA VM auto-start (will it fail due to NFS external disk not ready?).
Check: worker pods (will they fail if NFS not restored before pod scheduling?).
→ Run checklist.

### Scenario 5.4 — Power Flicker (Short Outage, UPS Holds)
Power out and back before UPS reaches shutdown threshold.
VMs stay running but NFS/NAS may restart.
Storage takes time to recover and start sharing.
Check: pods hanging on NFS mount during recovery window.
→ Run checklist.

### Scenario 5.5 — IPA Domain Down
Stop IPA server.
Check: K8s worker-to-master communication (IP-based or DNS-dependent? Check /etc/hosts).
Check: Vault cluster (certs signed by IPA — does Vault break?).
Check: Ansible runner connectivity to all nodes (fallback to root + trusted key via inventory).
Check: can you still SSH into nodes? (local accounts, emergency access).
Document: IPA restore procedure.
→ Run checklist.

### Scenario 5.6 — Proxmox Management Network Drop
Drop network between Proxmox host and management VLAN.
Check: impact on monitoring, self-healing automation, Proxmox API availability.
Can you still reach Proxmox via console?
→ Run checklist.

### Scenario 5.7 — Proxmox API Unavailable
Stop Proxmox API service (pveproxy).
Check: impact on auto-recovery scripts (Scenario 1.21), monitoring, VM management.
→ Run checklist.

### Task 5 — Observation Checklist (run after every scenario):
- [ ] Shutdown sequence completed in correct order
- [ ] All VMs and LXCs started after recovery
- [ ] NFS shares available and mounted
- [ ] Proxmox backup mount restored
- [ ] IPA external disk remounted
- [ ] IPA accessible (or: confirmed not needed for K8s comms)
- [ ] K8s cluster healthy (masters, workers, pods)
- [ ] Vault unsealed and serving
- [ ] WordPress accessible
- [ ] Ansible runner can reach all nodes
- [ ] Email notification sent via mgmt path

---


## Known SPOFs (Accepted):

- FreeIPA (single instance)
- NAS / NFS storage (single instance)
- External NGINX (single LXC)
- MariaDB (single instance)
- VPN Tunnel
- Router
- Switch
- AP