# Task 1b: Worker Node Failures

**Trigger:** Take down worker nodes in various combinations.
**Baseline:** WordPress browsing + video upload running throughout all scenarios.

---

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

---

### Observation Checklist (run after every scenario):
- [ ] WordPress accessible (browse + upload)
- [ ] DB integrity (no duplicate conflicts, no orphaned transactions)
- [ ] Pod scheduling and priority behavior
- [ ] Grafana: CPU, mem, pod restarts on remaining nodes
- [ ] Node recovery and rejoin cluster
