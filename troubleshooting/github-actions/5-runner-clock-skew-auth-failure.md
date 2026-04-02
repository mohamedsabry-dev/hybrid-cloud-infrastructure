# Case 5: GitHub Actions Runner Clock Skew Authentication Failure

## Status: RESOLVED
## Date: 2026-03-14

## Symptoms
- Runner shows "Offline" in GitHub Actions
- Runner service fails with: `The runner registration has been deleted from the server`
- Misleading error suggests re-registration needed

---

## Investigation

### Initial Error (misleading)
```
Failed to create a session. The runner registration has been deleted
from the server, please re-configure. Runner registrations are
automatically deleted for runners that have not connected to the
service recently.
```

### Real Error (in logs)
```bash
cat /opt/actions-runner/_diag/Runner_*.log | tail -50
```

```
VssOAuthTokenRequestException: The token is not valid until
03/14/2026 15:02:29. Current server time is 03/14/2026 13:02:56.
```

**Translation:** Runner clock is 2 hours ahead of GitHub servers.

---

## Root Cause Chain

```
DNS broken (old nameserver 192.168.0.1)
    ↓
NTP can't resolve pool.ntp.org
    ↓
Chrony can't sync time
    ↓
Host clock drifts 2 hours
    ↓
LXC inherits wrong time from host
    ↓
Runner OAuth tokens appear "from the future"
    ↓
GitHub rejects authentication
```

---

## Diagnosis Steps

### 1. Check runner logs
```bash
journalctl -u actions.runner.* -n 50 --no-pager
cat /opt/actions-runner/_diag/Runner_*.log | tail -50
```

### 2. Check host time
```bash
timedatectl
# Look for: System clock synchronized: no
```

### 3. Check NTP sources
```bash
chronyc sources -v
# Empty = no NTP servers reachable
```

### 4. Check DNS
```bash
cat /etc/resolv.conf
ping google.com  # Hangs if DNS broken
ping 8.8.8.8     # Works if network OK but DNS broken
```

---

## Fix

### 1. Fix DNS
```bash
cat > /etc/resolv.conf << 'EOF'
search lab.local
nameserver 192.168.100.1
nameserver 8.8.8.8
EOF
```

### 2. Sync time
```bash
timedatectl set-ntp true
systemctl restart chrony
chronyc makestep
chronyc sources
timedatectl
# Verify: System clock synchronized: yes
```

### 3. Restart runner
```bash
cd /opt/actions-runner
./svc.sh stop
./svc.sh start
./svc.sh status
```

---

## Quick Manual Time Fix (if NTP not working)

```bash
# Disable NTP first
timedatectl set-ntp false

# Set correct time manually
timedatectl set-time "HH:MM:00"

# Restart runner
cd /opt/actions-runner && ./svc.sh stop && ./svc.sh start
```

---

## Prevention

1. **Ensure DNS is correct** in `/etc/resolv.conf`
2. **Verify NTP is syncing** after network changes
3. **For isolated hosts** (no internet): sync from local NTP server
   ```bash
   # On host with internet (e.g., pve-dev)
   echo "allow 10.0.0.0/8" >> /etc/chrony/chrony.conf
   systemctl restart chrony

   # On isolated host (e.g., pve-prod)
   echo "server 10.0.5.110 iburst" >> /etc/chrony/chrony.conf
   systemctl restart chrony
   ```

---

## Key Lesson

**"Runner registration deleted"** error is often NOT about registration - check clock skew first.

OAuth tokens have timestamps. If your clock is ahead, tokens appear "not valid yet" to the server.

## Status
RESOLVED - Fixed DNS, NTP synced, runner back online
