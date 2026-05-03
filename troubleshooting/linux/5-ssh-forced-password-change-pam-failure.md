# TS-LNX-005 | 2026-05-03 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Linux
Sub-techs: OpenSSH, PAM, chage, passwd, SUID, sshd_config.d
Environment: DEV lab.local | Rocky Linux 10 | test1.lab.local (10.0.55.151)
Re-opened: No

_____________________________________________________________________

[Issue Description]
Users created with `chage -d 0` can't change their password over SSH or `su -`.
Prompt appears, user enters a strong new password, fails every time:

  passwd: Authentication token manipulation error
  passwd: password unchanged
  Connection to 10.0.55.151 closed.

Same password works fine with `passwd` command directly.

_____________________________________________________________________

[Analysis]

# Initial Check Notes:

Setup: useradd, chpasswd (temp password), chage -d 0, usermod -aG wheel,docker.
SSH from ansible → forced change prompt → entered new password → immediate fail.
Tried multiple strong passwords across multiple SSH sessions. All failed.

# Check 1: sshd logs

Command:
  journalctl -u sshd --no-pager -n 20

Output:
  sshd-session: pam_unix(sshd:account): expired password for user admin (root enforced)
  sshd-session: Accepted password for admin from 10.0.53.10 port 40056 ssh2
  sshd-session: pam_unix(sshd:session): session opened for user admin

Login succeeds. Password change fails. Logs show nothing about WHY.

# Check 2: ssh -vvv debug

Command:
  ssh -vvv admin@10.0.55.151

Output:
  WARNING: Your password has expired.
  You must change your password now and login again!
  Current password: debug3: obfuscate_keystroke_timing: starting: interval ~20ms
  debug3: Received SSH2_MSG_IGNORE (repeated)
  passwd: Authentication token manipulation error
  passwd: password unchanged
  debug3: receive packet: type 96
  debug2: channel 0: rcvd eof
  debug2: channel 0: output open -> drain
  debug2: channel 0: is dead

No PAM rejection reason in the debug output either. Just channel close.

# Check 3: shadow entry + home dir

Command:
  grep admin /etc/shadow
  ls -la /home/admin/

Output:
  admin:$y$j9T$...:0:0:99999:7:::
  drwx------. 2 admin admin 83 /home/admin

Normal. The :0: is what chage -d 0 sets.

# Check 4: Local reproduction (not SSH)

This was the turning point. From root, su - admin, then ran passwd:

  [admin@test1 ~]$ passwd
  Current password:
  New password:
  BAD PASSWORD: The password contains the user name in some form
  passwd: Authentication token manipulation error
  passwd: password unchanged
  [admin@test1 ~]$ passwd
  Current password:
  New password:
  Retype new password:
  passwd: password updated successfully

Two findings:
  1. passwd shows the actual rejection reason — SSH swallows it
  2. passwd allows retries within one session

Then created testuser to reproduce with a clean user. Set chage -d 0 and tested
su - from inside testuser session (not SSH):

  [testuser@test1 root]$ su - testuser
  Password:
  You are required to change your password immediately (administrator enforced).
  Current password:
  su: Authentication token manipulation error
  [testuser@test1 root]$ su - testuser
  Password:
  You are required to change your password immediately (administrator enforced).
  Current password:
  su: Authentication token manipulation error
  [testuser@test1 root]$ su - testuser
  Password:
  You are required to change your password immediately (administrator enforced).
  Current password:
  su: Authentication token manipulation error

All failed via su -. Then tried passwd from the same session:

  [testuser@test1 root]$ passwd
  Current password:
  New password:
  BAD PASSWORD: The password contains the user name in some form
  passwd: Authentication token manipulation error
  passwd: password unchanged
  [testuser@test1 root]$ passwd
  Current password:
  New password:
  BAD PASSWORD: The password fails the dictionary check - it is based on a dictionary word
  passwd: Authentication token manipulation error
  passwd: password unchanged
  [testuser@test1 root]$ passwd
  Current password:
  New password:
  Retype new password:
  passwd: password updated successfully

Same behavior. su - fails every time even with strong passwords. passwd eventually
accepts on retry. This proves the issue is NOT SSH-specific — su - has it too.

# Check 5: SUID bit

Command:
  ls -la /usr/bin/passwd

Output:
  -rwsr-xr-x. 1 root root 91424 Feb 25 02:00 /usr/bin/passwd

The "s" = SUID. passwd runs as root even when a normal user calls it.

# Suspected Root Cause

Not fully defined. The behavior points to SSH and su - not being capable of
handling expired password changes properly. When chage -d 0 marks a password
as expired, the change flow only works via passwd command or from root directly.
SSH and su - both fail with the generic "Authentication token manipulation error"
even with strong passwords that passwd accepts fine. The SUID bit on passwd
(runs as root) is likely the differentiator.

# Test: .bash_profile workaround

Instead of chage -d 0, inject passwd into .bash_profile:

  echo 'passwd && sed -i "/passwd/d" ~/.bash_profile' >> /home/admin/.bash_profile

Test:
  1. Deleted users, removed old SSH configs, ran fresh user_setup.py
  2. SSH login 1 → passwd ran → bad password → connection closed
  3. SSH login 2 → passwd ran → strong password → success → line self-removed
  4. SSH login 3 → clean shell, no prompt

Result: PASS

_____________________________________________________________________

[Final Root Cause]
Not confirmed. When chage -d 0 marks a password as expired, SSH and su -
cannot complete the forced password change — they fail with "Authentication
token manipulation error" regardless of password strength. The only way to
change an expired password is via the passwd command or from root directly.
The SUID bit on passwd (runs as root) is likely the differentiator but the
exact mechanism was not pinpointed.

_____________________________________________________________________

[Final Solution]
Replaced chage -d 0 with .bash_profile forced passwd call:

  echo 'passwd && sed -i "/passwd/d" ~/.bash_profile' >> /home/<user>/.bash_profile

  - First login → passwd runs (SUID root)
  - Success → sed removes the line (self-cleaning)
  - Failure → user sees real error, retries next login
  - Ctrl+C → passwd fails → sed doesn't run → next login forces again

Prerequisite: cloud-init disables PasswordAuthentication. Need a drop-in:

  echo -e 'Match User admin\n    PasswordAuthentication yes' > /etc/ssh/sshd_config.d/99-admin-password.conf
  systemctl restart sshd

99-* prefix overrides 50-cloud-init.conf (load order).

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
If user bypasses .bash_profile (forced command, rsync), the change won't trigger.
Acceptable for lab.

_____________________________________________________________________

[References]
-

_____________________________________________________________________

[Draft Notes]

Dead ends during investigation:
  - ssh -vvv: showed channel close, no PAM detail
  - sshd journal: "Accepted password" then session close, no rejection reason
