Remediation Self-Healing — From Node Failure to Automated Recovery (Summary Trace)
====================================================================================

pre-trace (one-time setup):
  Proxmox API user k8s-pve@pve with token "remediation" stored in Vault
    → MikroTik firewall: master VLAN → Proxmox:8006 (workers blocked)
    → K8s RBAC: read-only nodes/pods, PriorityClass 1M (survives eviction)

pod deploys on master node (1 replica, control-plane only)
  → vault-agent sidecar injects Proxmox credentials to /vault/secrets/proxmox-creds
    → python script loads creds → creates ProxmoxAPI client (token auth)
      → initial 300s sleep (cluster stabilization after boot)

→ Phase 1: for each worker in NODE_MAP (worker → VMID mapping):
    → K8s API: v1.read_node() → check conditions type=Ready
      → Ready=True → skip → Ready=False → added to suspect list

→ Phase 1.5 (dev only): sleep 180s → re-check suspects
    → recovered during delay → removed from list
    → still NotReady → confirmed unhealthy

→ Phase 2: for each confirmed unhealthy node:
    → network: pod (master VLAN) → MikroTik rule → Proxmox VLAN → port 8006

  → Attempt 1: get_vm_status() → status-aware reboot
      → running: reboot.post() (ACPI) → stopped: start.post()
        → alert to Alertmanager: "reboot - initiated" (warning)

  → Attempt 2: hard reset
      → running: reset.post() (power yank) → stopped: start.post()
        → alert: "reset - initiated" (warning)

  → Attempt 3 (prod only): restore from backup
      → query NAS storage for latest vzdump backup (sorted by ctime)
        → stop VM (30s) → delete VM (10s) → restore at same VMID + start
          → 120s buffer (async restore ~3.5 min actual)
            → alert: "restore - initiated" (critical)

  → all attempts exhausted → alert: "all-attempts - exhausted" (critical)
    → no further action until manual intervention

→ recovery detected on any cycle: node Ready again
  → counter reset to 0 → alert: "recovery - node healthy" (info)

→ all alerts: POST alertmanager.monitoring.svc:9093/api/v2/alerts
  → Alertmanager routes → SMTP relay → email notification
