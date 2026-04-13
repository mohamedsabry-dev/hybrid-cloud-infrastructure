# Task 1d: Auto-Recovery via Proxmox API

**Trigger:** Test automated recovery procedure for downed nodes.
**Baseline:** WordPress browsing + video upload running throughout all scenarios.
**Prerequisite:** Automation tooling (Lambda/monitoring) must be configured.

---

### Scenario 1.15 — Auto-Recovery via Proxmox API
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

### Observation Checklist:
- [ ] Node rejoins cluster
- [ ] App + etcd healthy
- [ ] Email notification received
- [ ] Backup restoration successful
- [ ] Log analysis possible from copied node
- [ ] **Grafana:** node metrics resume after recovery
- [ ] **Prometheus:** scraping targets re-appear, no gaps in metrics
- [ ] **Loki:** logs show recovery sequence, compare with pre-failure state
