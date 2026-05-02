# Open Tickets

Non-resolved cases across all categories. Last updated: 2026-04-30.

### Workaround Applied / Temp Closed

| Ticket | Status | What Happened |
|--------|--------|---------------|
| [TS-IDN-005](identity/5-freeipa-server-sssd-sudo.md) | WORKAROUND APPLIED | Sudo rules work correctly on all IPA clients but not on the FreeIPA server itself |
| [TS-IDN-010](identity/10-sssd-crash-boot-keytab-read-failure.md) | WORKAROUND APPLIED | SSSD failed to start after backup incident reboot on master1 — keytab read failure, restart fixed, root cause not identified |
| [TS-K8S-010](kubernetes/10-wordpress-admin-password-hash-reset.md) | TEMP CLOSED | WordPress admin login fails with "incorrect password" despite correct password |
| [TS-K8S-038](kubernetes/38-qemu-guest-agent-cpu-loop.md) | WORKAROUND APPLIED | QEMU Guest Agent (qemu-ga) entered a busy loop consuming 98% CPU on master. Trigger still unidentified — IO storm watchdog (TS-PVE-017) catches and resets if it recurs. |
| [TS-K8S-050](kubernetes/reference/50-remediation-pod-backup-window-race-condition.md) | WORKAROUND APPLIED | Remediation pod vs vzdump suspend race condition. K8s nodes excluded from backup (TS-PVE-020), dev remediation has 3-min confirmation delay. Collision path eliminated on dev, reduced on prod. |
| [TS-K8S-055](kubernetes/55-apiserver-etcd-grpc-connection-warnings.md) | WORKAROUND APPLIED | API server gRPC warnings to etcd every ~30s — upstream etcd client v3.6.x resolver bug (etcd-io/etcd#21660). Promtail drop filter applied to suppress log noise. |
| [TS-NET-001](network/1-static-route-ssh-disconnect.md) | WORKAROUND APPLIED | SSH connections disconnect after ~30 seconds when routing 10.x traffic through |

### Suspended

| Ticket | Status | What Happened |
|--------|--------|---------------|
| [TS-LNX-004](linux/4-cloud-init-etc-hosts-ownership.md) | SUSPENDED | Ansible playbook k8s_hosts_fallback.yml adds entries to /etc/hosts, but cloud-init resets ownership |

**Total: 8 open (7 workaround/temp closed, 1 suspended)**
