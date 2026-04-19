# Issue: Proxmox Host CPU/IO Spike - VMs Stuck at Boot

**Status:** WORKAROUND APPLIED (Reboot Proxmox host)
**Date Discovered:** 2026-04-19
**Severity:** Critical
**Root Cause:** NOT IDENTIFIED

---

## Summary

Proxmox host experienced severe CPU and IO spike causing all VMs to become unresponsive. VMs stuck at kernel boot screen, unable to progress. Multiple K8s masters showed segfaults before becoming completely stuck.

---

## Symptoms

1. **All VMs unresponsive** - couldn't SSH, API server down
2. **VMs stuck at boot** - "Booting Rocky Linux" screen, no progress
3. **Proxmox host metrics:**
   - CPU spike to abnormal levels
   - IO wait above 50%
4. **VM processes showing high CPU:**
   ```
   1010 (master1) - 99.0% CPU
   1011 (master2) - 98.7% CPU
   ```
5. **Segfault observed in VM console:**
   ```
   rs:main Q:Reg[1192]: segfault at 0 ip 0000560a9e7b60ab sp 00007f6785596b470 error 4 in rsyslogd
   ```
6. **HAProxy reporting no backend servers:**
   ```
   haproxy[1218]: backend k8s_masters has no server available!
   ```

---

## Timeline

| Time | Event |
|------|-------|
| 2026-04-18 ~23:00 | Started DR testing (multiple node shutdowns/restarts) |
| 2026-04-19 ~00:15 | DR Test 4 completed successfully |
| 2026-04-19 ~00:50 | Noticed API server issues on master1 |
| 2026-04-19 ~00:55 | API server crash loop, "no relationship found" errors |
| 2026-04-19 ~01:00 | HAProxy reporting no masters available |
| 2026-04-19 ~01:05 | Attempted VM resets - VMs stuck at boot |
| 2026-04-19 ~01:10 | Identified Proxmox host CPU/IO spike |
| 2026-04-19 ~01:15 | Rebooted Proxmox host |

---

## Root Cause Investigation

### Suspected Contributing Factors

1. **Extended DR testing** - Multiple shutdown/start cycles over 2 days
2. **qemu-ga EAGAIN busy loop** - Multiple occurrences documented (issue #38)
3. **High VM churn** - Frequent pod evictions, restarts, scheduling
4. **Possible resource exhaustion** on Proxmox host

### Evidence Collected

**VM CPU from Proxmox:**
```
ps aux | grep qemu
1010 (master1) - 99.0% CPU
1011 (master2) - 98.7% CPU
1012 (master3) - 54.6% CPU
```

**qemu-ga not responding:**
```
qm guest cmd 1010 ping
QEMU guest agent is not running
```

### What We Don't Know

- Exact trigger for Proxmox host instability
- Whether qemu-ga loops caused cascading host issues
- If there was memory exhaustion on host
- If NFS storage had issues

---

## Workaround Applied

**Rebooted Proxmox host**

```bash
# On Proxmox host
reboot
```

After reboot:
- All VMs started normally
- K8s cluster recovered
- No further issues observed

---

## Prevention

1. **Monitor Proxmox host resources** during DR testing
2. **Limit consecutive DR tests** - allow host to stabilize between tests
3. **Consider disabling qemu-ga** on K8s masters (see issue #38)
4. **Add Proxmox host monitoring alerts** for:
   - CPU > 90% sustained
   - IO wait > 40%
   - Memory exhaustion

---

## Related Issues

- `troubleshooting/kubernetes/38-qemu-guest-agent-cpu-loop.md` - qemu-ga busy loop
- `troubleshooting/kubernetes/43-noexecute-taint-not-applied.md` - DR testing that preceded this
- `troubleshooting/proxmox/15-proxmox-crash-during-backup-unknown-cause.md` - Similar unknown crash

---

## Next Steps

1. Monitor for recurrence
2. Check Proxmox logs after next occurrence:
   ```bash
   journalctl -u pvedaemon --since "1 hour ago"
   journalctl -u pveproxy --since "1 hour ago"
   dmesg | grep -iE "error|fail|oom"
   ```
3. Consider reducing DR test intensity
4. Review qemu-ga mitigation options

---

## Lessons Learned

- Proxmox host stability is critical for K8s cluster recovery
- Multiple rapid VM operations can destabilize the host
- Always have Proxmox console access as fallback
- Host reboot is a valid recovery option when VMs are stuck
