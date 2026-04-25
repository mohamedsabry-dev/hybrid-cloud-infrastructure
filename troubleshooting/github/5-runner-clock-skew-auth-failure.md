# TS-GH-005 | 2026-03-14 | RESOLVED
_____________________________________________________________________

[Info]
Domain: GitHub Actions
Sub-techs: Self-hosted runner, OAuth token, Chrony NTP, DNS, LXC time inheritance
Environment: LXC container on Proxmox
Re-opened: No

_____________________________________________________________________

[Issue Description]
Runner shows Offline in GitHub Actions with a misleading error message about
registration being deleted. Real cause was clock skew — runner clock was 2 hours
ahead of GitHub servers.

Displayed error:
  Failed to create a session. The runner registration has been deleted from the
  server, please re-configure. Runner registrations are automatically deleted for
  runners that have not connected to the service recently.

Actual error in runner diagnostic logs:
  VssOAuthTokenRequestException: The token is not valid until 03/14/2026 15:02:29.
  Current server time is 03/14/2026 13:02:56.

Runner clock was 2 hours ahead — OAuth tokens appeared to GitHub as coming from
the future.

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
The displayed error pointed at registration but it felt wrong — checked runner
diagnostic logs directly instead of trusting the UI message.

Command:
  cat /opt/actions-runner/_diag/Runner_*.log | tail -50

Output:
  VssOAuthTokenRequestException: token not valid until 15:02:29,
  current server time 13:02:56 — clock 2 hours ahead.

Checked system time sync:

Command:
  timedatectl

Output:
  System clock synchronized: no

Checked NTP sources:

Command:
  chronyc sources -v

Output:
  Empty — no NTP servers reachable at all.

Checked DNS since NTP pool hostnames need to resolve:

Command:
  cat /etc/resolv.conf
  ping google.com
  ping 8.8.8.8

Output:
  nameserver 192.168.0.1  ← old/wrong nameserver
  ping google.com hangs
  ping 8.8.8.8 works

DNS broken — NTP pool hostnames cannot resolve, chrony cannot sync,
host clock drifted, LXC inherited the wrong time.

Failure chain:
  DNS broken (old nameserver 192.168.0.1)
    → NTP cannot resolve pool.ntp.org
    → Chrony cannot sync time
    → Host clock drifts 2 hours
    → LXC inherits wrong time
    → Runner OAuth tokens appear "from the future"
    → GitHub rejects authentication


# Suspected Root Cause
DNS misconfiguration (stale nameserver 192.168.0.1) broke NTP hostname resolution.
Chrony could not sync. Host clock drifted 2 hours. LXC inherited the wrong time.
Runner OAuth tokens had timestamps ahead of GitHub server time — rejected.


# More Checks Notes:
Confirmed NTP works after DNS is fixed:

Command:
  chronyc sources -v  (after fixing resolv.conf)

Output:
  NTP sources visible and reachable.


# Suspected Solution
Fix DNS in resolv.conf, force time sync via chronyc makestep, restart runner.


# Test
Fixed resolv.conf, ran chronyc makestep, restarted runner service.

Command:
  timedatectl
  ./svc.sh status

Result: PASS — System clock synchronized: yes, runner back online.

_____________________________________________________________________

[Final Root Cause]
Stale nameserver (192.168.0.1) in /etc/resolv.conf broke DNS resolution.
Chrony could not resolve pool.ntp.org, stopped syncing, host clock drifted
2 hours forward. LXC container inherited wrong time from host. Runner OAuth
tokens appeared timestamped in the future — GitHub rejected authentication
and surfaced a misleading "registration deleted" error instead of a clock error.

_____________________________________________________________________

[Final Solution]
Three steps — fix DNS, sync time, restart runner:

  # 1. Fix DNS
  cat > /etc/resolv.conf << 'EOF'
  search lab.local
  nameserver 192.168.100.1
  nameserver 8.8.8.8
  EOF

  # 2. Sync time
  timedatectl set-ntp true
  systemctl restart chrony
  chronyc makestep
  timedatectl  # verify: System clock synchronized: yes

  # 3. Restart runner
  cd /opt/actions-runner
  ./svc.sh stop && ./svc.sh start

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: Standard DNS and NTP maintenance — no infrastructure impact.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Key lesson: "Runner registration deleted" is often NOT about registration.
Check clock skew first — OAuth tokens have timestamps and GitHub will reject
tokens that appear to come from the future.

Quick fix if NTP cannot be restored immediately:
  timedatectl set-ntp false
  timedatectl set-time "HH:MM:00"
  cd /opt/actions-runner && ./svc.sh stop && ./svc.sh start

For isolated hosts with no internet — sync from local NTP server:
  # On host with internet (e.g. pve-dev)
  echo "allow 10.0.0.0/8" >> /etc/chrony/chrony.conf
  systemctl restart chrony

  # On isolated host (e.g. pve-prod)
  echo "server 10.0.5.110 iburst" >> /etc/chrony/chrony.conf
  systemctl restart chrony

Related: TS-GH-001 — runner stuck after reboot (different root cause, same runner)