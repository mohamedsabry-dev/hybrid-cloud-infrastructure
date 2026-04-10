# Task 1: Kill Compute

**Trigger:** Take down pods, workers, masters, vault nodes in various combinations.
**Baseline:** WordPress browsing + video upload running throughout all scenarios.

---

### Scenario 1.1 — Single Pod Kill
Kill 1 pod for each critical component.

- Action: Kill pod (restart, recreate, force delete) for each:
  - WordPress
  - MariaDB
  - vault-injector
  - ingress-nginx
  - flux
  - prometheus
  - exporters
- Check: Pod restarts automatically
- Check: Service remains available (or recovers quickly)

→ Run checklist.

### Scenario 1.2 — Full Pod Scale Loss
Kill all replicas (3 of 3) for each component.

- Action: `kubectl delete pod -l app=<component> --all`
- Check: All pods recreated by controller
- Check: Service downtime duration
- Check: Flux reconciliation status

→ Run checklist.

### Scenario 1.3 — Mid-Upload Pod Kill
Kill the pod handling an active upload.

- Action: Start video upload to WordPress
- Action: Identify serving pod via nginx logs
- Action: Kill that pod mid-upload
- Check: Upload data persisted or lost?
- Check: DB transaction state — committed or rolled back?
- Check: Can same file be re-uploaded? (duplicate name conflict?)

→ Run checklist.

### Scenario 1.4 — Pod Eviction Under Pressure
Observe eviction priority when node is under pressure.

- Action: Create memory/CPU pressure on a worker node
- Action: Observe which pods get evicted first
- Check: Document eviction order
- Expected order: CSI > ingress > flux > app > exporters (verify actual)
- Check: Critical system pods survive

→ Run checklist.

### Scenario 1.5 — Single Worker Node Down
Restart or force shutdown 1 worker node.

- Action: Graceful restart worker node
- Check: Pods reschedule to other workers
- Measure: Time from NotReady → pods running elsewhere
- Action: Repeat with force shutdown (simulate crash)
- Check: Same behavior, different timing?

→ Run checklist.

### Scenario 1.6 — Partial Worker Loss (2 of 3)
Force shutdown 2 of 3 workers.

- Action: Force shutdown 2 worker nodes
- Check: Remaining worker handles all pods?
- Check: Resource pressure on surviving worker
- Check: Any pods stuck in Pending (insufficient resources)?

→ Run checklist.

### Scenario 1.7 — Full Worker Loss (3 of 3)
Force shutdown all 3 workers.

- Action: Force shutdown all worker nodes
- Check: All app pods down (expected)
- Check: Remediation pod runs on master — does it detect this?
- Check: Control plane still functional (masters up)
- Recovery: Start workers → pods reschedule

→ Run checklist.

### Scenario 1.8 — Mid-Upload Worker Kill
Kill the worker node handling an active upload.

- Action: Start video upload to WordPress
- Action: Identify worker node via nginx/pod placement
- Action: Force shutdown that worker mid-upload
- Check: Upload data persistence
- Check: DB transaction state
- Check: Can same file be re-uploaded?

→ Run checklist.

### Scenario 1.9 — Single Master Node Down
Restart or force shutdown 1 master.

- Action: Graceful restart 1 master
- Check: `kubectl` commands still work (other masters serving)
- Check: etcd quorum maintained (2 of 3)
- Action: Repeat with force shutdown
- Check: etcd leader election occurs

→ Run checklist.

### Scenario 1.10 — Partial Master Loss (2 of 3)
Force shutdown 2 of 3 masters.

- Action: Force shutdown 2 master nodes
- Check: etcd quorum LOST (only 1 of 3)
- Check: API server behavior — read-only or unavailable?
- Check: Existing pods still running (kubelet independent)
- Recovery: Start 1 master → quorum restored

→ Run checklist.

### Scenario 1.11 — Single Vault Node Down
Restart or force shutdown 1 vault pod.

- Action: Graceful restart 1 vault pod
- Check: Raft leader election (if leader killed)
- Check: Vault remains unsealed
- Action: Repeat with force kill
- Check: Same behavior

→ Run checklist.

### Scenario 1.12 — Vault Quorum Loss (2 of 3)
Kill 2 vault nodes, lose quorum.

- Action: Kill 2 vault pods
- Check: Vault cluster unavailable (no quorum)
- Check: Existing pods still serving with cached secrets?
- Check: New pods can fetch secrets? (expected: no)
- Recovery: Start vault pods → quorum restored

→ Run checklist.

### Scenario 1.13 — Vault Seal/Unseal Cycle
Test manual seal and auto-unseal behavior.

- Action: Manually seal vault (`vault operator seal`)
- Check: AWS KMS auto-unseal triggers
- Check: Vault becomes unsealed automatically
- Check: App pods continue serving
- Action: Break auto-unseal (remove/change AWS KMS secrets)
- Action: Manual recovery procedure
- Check: App recovers after manual unseal

→ Run checklist.

### Scenario 1.14 — Combined: 2 Workers + 1 Master
Simultaneous partial failure.

- Action: Force shutdown 2 workers + 1 master
- Check: etcd quorum maintained (2 masters)
- Check: Pods reschedule to remaining worker
- Check: API server responsive
- Check: Resource pressure on surviving worker

→ Run checklist.

### Scenario 1.15 — Combined: 2 Workers + 2 Masters
Severe combined failure.

- Action: Force shutdown 2 workers + 2 masters
- Check: etcd quorum LOST
- Check: 1 worker still running pods (kubelet works)
- Check: No new scheduling possible
- Recovery: Start 1 master → quorum restored → scheduling resumes

→ Run checklist.

### Scenario 1.16 — Combined: 3 Workers + 1 Master
All worker capacity gone, partial control plane.

- Action: Force shutdown all 3 workers + 1 master
- Check: All app pods down
- Check: Control plane functional (2 masters, quorum OK)
- Check: Remediation detection
- Recovery: Start workers → pods reschedule

→ Run checklist.

### Scenario 1.17 — Auto-Recovery via Proxmox API
Test automated recovery procedure for downed nodes.

- Action: Trigger after node stays down for extended period
- Procedure:
  1. Proxmox API → force stop the node
  2. Copy node to different VMID/CTID (for log analysis)
  3. Restore latest backup of that node
  4. Start the node
- Check: Node rejoins cluster (K8s or Vault)
- Check: App + etcd health
- Check: Email notification sent

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
