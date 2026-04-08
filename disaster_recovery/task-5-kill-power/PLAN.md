# Task 5: Kill Power / Infrastructure

**Trigger:** Simulate full or partial power loss and infrastructure-level failures.
**Baseline:** Full environment running normally before each scenario.
**Prerequisite:** Task 0 (Backup & Restore) validated first.

---

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