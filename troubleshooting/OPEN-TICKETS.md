# Open Tickets

Non-resolved cases across all categories. Last updated: 2026-04-24.

| Ticket | Status | What Happened |
|--------|--------|---------------|
| [TS-IDN-005](identity/5-freeipa-server-sssd-sudo.md) | WORKAROUND APPLIED | Sudo rules work correctly on all IPA clients but not on the FreeIPA server itself |
| [TS-IDN-010](identity/10-sssd-crash-boot-keytab-read-failure.md) | WORKAROUND APPLIED | SSSD failed to start after backup incident reboot on master1 — keytab read failure, restart fixed, root cause not identified |
| [TS-K8S-010](kubernetes/10-wordpress-admin-password-hash-reset.md) | TEMP CLOSED | WordPress admin login fails with "incorrect password" despite correct password |
| [TS-K8S-025](kubernetes/25-promtail-vault-namespace-logs.md) | SUSPENDED | Promtail not collecting logs from Vault namespace. Also confirmed not collecting |
| [TS-K8S-038](kubernetes/38-qemu-guest-agent-cpu-loop.md) | TRIGGER NOT IDENTIFIED | QEMU Guest Agent (qemu-ga) entered a busy loop consuming 98% CPU on master |
| [TS-K8S-039](kubernetes/39-kube-system-targetdown-false-positives.md) | SUSPENDED | Prometheus firing TargetDown and etcd alerts for kube-system components despite |
| [TS-LNX-004](linux/4-cloud-init-etc-hosts-ownership.md) | PENDING (Decision Later) | Ansible playbook k8s_hosts_fallback.yml adds entries to /etc/hosts, but cloud-in |
| [TS-NET-001](network/1-static-route-ssh-disconnect.md) | WORKAROUND APPLIED | SSH connections disconnect after ~30 seconds when routing 10.x traffic through |
| [TS-PVE-015](proxmox/15-proxmox-crash-during-backup-unknown-cause.md) | UNRESOLVED (RE-OPENED) | Re-opened 2026-04-23: confirmed pattern on both envs, backup schedule overlap causes NAS saturation + K8s master CrashLoopBackOff |
| [TS-PVE-017](proxmox/17-proxmox-host-cpu-io-spike-vms-stuck.md) | WORKAROUND APPLIED | Proxmox host hit a severe CPU and IO spike — all VMs became unresponsive. |
| [TS-PVE-018](proxmox/18-prod-server-complete-shutdown-during-backup.md) | WORKAROUND APPLIED | temperature_monitor.sh (80°C threshold) triggered graceful shutdown during vzdump zstd compression spike to 91°C. Temp fix: shutdown action commented out — thermal protection disabled. |

| [TS-K8S-050](kubernetes/50-remediation-pod-backup-window-race-condition.md) | PENDING | Preventive: remediation pod health check may collide with vzdump suspend phase — race condition not yet triggered |

**Total: 12 open**
