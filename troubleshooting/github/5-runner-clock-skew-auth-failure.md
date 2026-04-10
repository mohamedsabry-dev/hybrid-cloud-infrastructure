# TS-GH-005 | 2026-03-14 | RESOLVED

## 1. Context
- System: GitHub Actions self-hosted runner
- Environment: LXC container on Proxmox
- Related components: Chrony NTP, DNS resolution, OAuth authentication

## 2. Issue
- Symptom: Runner shows "Offline" in GitHub Actions
- Error:
```
Failed to create a session. The runner registration has been deleted
from the server, please re-configure. Runner registrations are
automatically deleted for runners that have not connected to the
service recently.
```

**Real error (in runner logs):**
```bash
cat /opt/actions-runner/_diag/Runner_*.log | tail -50
```
```
VssOAuthTokenRequestException: The token is not valid until
03/14/2026 15:02:29. Current server time is 03/14/2026 13:02:56.
```
**Translation:** Runner clock is 2 hours ahead of GitHub servers.

## 3. Analysis

**Check 1: Runner logs**
```bash
journalctl -u actions.runner.* -n 50 --no-pager
cat /opt/actions-runner/_diag/Runner_*.log | tail -50
```
Finding: OAuth token timestamp error - clock is ahead.

**Check 2: Host time**
```bash
timedatectl
# System clock synchronized: no
```
Finding: System clock not synchronized.

**Check 3: NTP sources**
```bash
chronyc sources -v
# Empty = no NTP servers reachable
```
Finding: No NTP servers reachable.

**Check 4: DNS**
```bash
cat /etc/resolv.conf
# nameserver 192.168.0.1  ← old/wrong nameserver

ping google.com  # Hangs
ping 8.8.8.8     # Works
```
Finding: DNS broken - can't resolve NTP pool hostnames.

## 4. Root Cause
> DNS misconfiguration (old nameserver 192.168.0.1) broke NTP resolution. Chrony couldn't sync time, host clock drifted 2 hours, LXC inherited wrong time. Runner OAuth tokens appeared "from the future" to GitHub servers.

**Chain:**
```
DNS broken (old nameserver)
    ↓
NTP can't resolve pool.ntp.org
    ↓
Chrony can't sync time
    ↓
Host clock drifts 2 hours
    ↓
LXC inherits wrong time
    ↓
Runner OAuth tokens "from the future"
    ↓
GitHub rejects authentication
```

## 5. Solution
> Fix DNS, sync time, restart runner.

**Step 1: Fix DNS**
```bash
cat > /etc/resolv.conf << 'EOF'
search lab.local
nameserver 192.168.100.1
nameserver 8.8.8.8
EOF
```

**Step 2: Sync time**
```bash
timedatectl set-ntp true
systemctl restart chrony
chronyc makestep
chronyc sources
timedatectl
# Verify: System clock synchronized: yes
```

**Step 3: Restart runner**
```bash
cd /opt/actions-runner
./svc.sh stop
./svc.sh start
./svc.sh status
```

## 6. Solution Risk
- Risk level: LOW
- Potential impact: None - fixing DNS and NTP is standard maintenance

## 7. Impact After Fix
- Observed: Runner back online
- Time synchronized correctly
- OAuth authentication working

## 8. Notes

**Quick manual time fix (if NTP not working):**
```bash
# Disable NTP first
timedatectl set-ntp false

# Set correct time manually
timedatectl set-time "HH:MM:00"

# Restart runner
cd /opt/actions-runner && ./svc.sh stop && ./svc.sh start
```

**For isolated hosts (no internet) - sync from local NTP server:**
```bash
# On host with internet (e.g., pve-dev)
echo "allow 10.0.0.0/8" >> /etc/chrony/chrony.conf
systemctl restart chrony

# On isolated host (e.g., pve-prod)
echo "server 10.0.5.110 iburst" >> /etc/chrony/chrony.conf
systemctl restart chrony
```

**Key lesson:** "Runner registration deleted" error is often NOT about registration - check clock skew first. OAuth tokens have timestamps; if clock is ahead, tokens appear "not valid yet" to the server.

**Related:** TS-GH-001 (runner stuck after reboot)

## 9. Workaround (if any)
> Manually set correct time with `timedatectl set-time` if NTP cannot be fixed immediately.
