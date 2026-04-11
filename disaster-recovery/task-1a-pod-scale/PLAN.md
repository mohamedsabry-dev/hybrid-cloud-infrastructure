# Task 1a: Pod Scale Failures

**Trigger:** Kill all replicas, mid-upload failures, eviction pressure.
**Baseline:** WordPress browsing + video upload running throughout all scenarios.

---

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

---

### Observation Checklist (run after every scenario):
- [ ] WordPress accessible (browse + upload)
- [ ] DB integrity (no duplicate conflicts, no orphaned transactions)
- [ ] Flux reconciliation status
- [ ] Pod scheduling and priority behavior
- [ ] Grafana: CPU, mem, pod restarts on remaining nodes
