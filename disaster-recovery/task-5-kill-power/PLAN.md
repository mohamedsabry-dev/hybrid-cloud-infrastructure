# Task 5: Kill Power / Infrastructure

**Trigger:** Simulate full or partial power loss and infrastructure-level failures.
**Baseline:** Full environment running normally before each scenario.
**Prerequisite:** Task 0 (Backup & Restore) validated first.

---

### Scenario 5.1 — Graceful Power Down (UPS Triggered)
Simulate electricity loss triggering UPS shutdown script.

- Action: Trigger UPS shutdown script (or simulate)
- Check: Shutdown order executes correctly:
  1. App pods
  2. K8s workers
  3. K8s masters
  4. Vault
  5. Proxmox
- Check: Each component shuts down cleanly
- Check: No data corruption

→ Run checklist.

### Scenario 5.2 — Graceful Power Down with NFS Dependency
Handle NFS mount before Proxmox shutdown.

- Action: Before Proxmox shutdown: `umount` NFS backup storage
- Check: Proxmox shuts down cleanly (no hang on NFS mount)
- Recovery: After power up: remount NFS before starting VMs
- Check: NFS mount successful before VM start

→ Run checklist.

### Scenario 5.3 — Full Recovery Boot Sequence
Power everything back on after graceful shutdown.

- Action: Boot in order:
  1. NAS/NFS
  2. Proxmox
  3. IPA
  4. Vault
  5. K8s masters
  6. K8s workers
  7. App pods
- Check: IPA VM auto-start — does it fail if NFS external disk not ready?
- Check: Worker pods — do they fail if NFS not restored before scheduling?
- Check: All services healthy after boot sequence

→ Run checklist.

### Scenario 5.4 — Power Flicker (Short Outage, UPS Holds)
Power out and back before UPS triggers shutdown.

- Action: Simulate brief power loss (UPS holds, no shutdown)
- Check: VMs stay running
- Check: NAS/NFS may restart (battery-backed or not?)
- Check: Storage takes time to recover and start sharing
- Check: Pods hanging on NFS mount during recovery window
- Check: Auto-recovery once NFS available

→ Run checklist.

### Scenario 5.5 — IPA Domain Down
Stop FreeIPA server, test DNS/auth dependencies.

- Action: Stop IPA server (VM shutdown or service stop)
- Check: K8s worker-to-master communication
  - IP-based or DNS-dependent?
  - Check `/etc/hosts` on nodes
- Check: Vault cluster — certs signed by IPA, does Vault break?
- Check: Ansible runner connectivity
  - Fallback to root + trusted key via inventory?
- Check: SSH access to nodes — local accounts, emergency access?
- Document: IPA restore procedure

→ Run checklist.

### Scenario 5.6 — Proxmox API Unavailable
Stop Proxmox API service.

- Action: Stop `pveproxy` service on Proxmox
- Check: VMs/LXCs still running (expected: yes)
- Check: Impact on auto-recovery scripts (remediation)
- Check: Impact on monitoring dashboards
- Check: Impact on VM management (no UI/API access)
- Recovery: Start `pveproxy` service
- Check: API access restored

→ Run checklist.

---

### Observation Checklist (run after every scenario):
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
- [ ] **Grafana:** all dashboards loading, no data gaps during outage
- [ ] **Prometheus:** scraping resumed, check for metric gaps in time series
- [ ] **Loki:** logs resume after boot, check startup sequence logs for errors
