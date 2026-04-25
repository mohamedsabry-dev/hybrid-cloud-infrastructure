# Open Tickets

Non-resolved cases across all categories. Last updated: 2026-04-25.

| Ticket | Status | What Happened |
|--------|--------|---------------|
| [TS-IDN-005](identity/5-freeipa-server-sssd-sudo.md) | WORKAROUND APPLIED | Sudo rules work correctly on all IPA clients but not on the FreeIPA server itself |
| [TS-IDN-010](identity/10-sssd-crash-boot-keytab-read-failure.md) | WORKAROUND APPLIED | SSSD failed to start after backup incident reboot on master1 — keytab read failure, restart fixed, root cause not identified |
| [TS-K8S-010](kubernetes/10-wordpress-admin-password-hash-reset.md) | TEMP CLOSED | WordPress admin login fails with "incorrect password" despite correct password |
| [TS-K8S-025](kubernetes/25-promtail-vault-namespace-logs.md) | SUSPENDED | Promtail not collecting logs from Vault namespace. Also confirmed not collecting |
| [TS-K8S-038](kubernetes/38-qemu-guest-agent-cpu-loop.md) | WORKAROUND APPLIED | QEMU Guest Agent (qemu-ga) entered a busy loop consuming 98% CPU on master. Trigger still unidentified — IO storm watchdog (TS-PVE-017) catches and resets if it recurs. |
| [TS-K8S-039](kubernetes/39-kube-system-targetdown-false-positives.md) | SUSPENDED | Prometheus firing TargetDown and etcd alerts for kube-system components despite |
| [TS-K8S-050](kubernetes/reference/50-remediation-pod-backup-window-race-condition.md) | WORKAROUND APPLIED | Remediation pod vs vzdump suspend race condition. K8s nodes excluded from backup (TS-PVE-020), dev remediation has 3-min confirmation delay. Collision path eliminated on dev, reduced on prod. |
| [TS-LNX-004](linux/4-cloud-init-etc-hosts-ownership.md) | SUSPENDED | Ansible playbook k8s_hosts_fallback.yml adds entries to /etc/hosts, but cloud-init resets ownership |
| [TS-NET-001](network/1-static-route-ssh-disconnect.md) | WORKAROUND APPLIED | SSH connections disconnect after ~30 seconds when routing 10.x traffic through |
**Total: 9 open**
