# TS-IDN-010 | 2026-04-24 | WORKAROUND APPLIED | INCIDENT
_____________________________________________________________________

[Info]
Domain: FreeIPA / SSSD / Kerberos
Sub-techs: SSSD, keytab, IPA backend, GSSAPI, vzdump backup suspend
Environment: pve-dev (k8s-master1)
Re-opened: No

_____________________________________________________________________

[Issue Description]
REAL INCIDENT -- discovered during TS-PVE-015 investigation.

After k8s-master1 rebooted following the backup incident (TS-PVE-015), SSSD
failed to start and stayed in `failed` state for 12+ hours (14:13 → 02:51).
All domain user logins to master1 were broken — `su k8s_admin` returned
"user does not exist", SSH with password fell back to keyboard-interactive
then failed.

Other nodes (master2, master3, workers) were unaffected — same domain users
could log in normally.

```
[root@k8s-master1 ~]# su k8s_admin
su: user k8s_admin does not exist or the user entry does not contain all the required fields

# SSH debug showed publickey rejected (expected — no keys deployed for this user),
# then keyboard-interactive password prompt → auth failure
# because SSSD was down and couldn't resolve the domain user
```

_____________________________________________________________________

[Analysis]

# Step 1: Check SSSD status
```
systemctl status sssd
× sssd.service - System Security Services Daemon
     Active: failed (Result: exit-code) since Thu 2026-04-23 14:13:31 EET; 11h ago
    Process: 1016 ExecStart=/usr/sbin/sssd -i (code=exited, status=1/FAILURE)
```

SSSD crashed 8 seconds after startup attempt. Failed since boot at 14:13.

# Step 2: Check SSSD logs — find the error chain
```
# From /var/log/sssd/sssd_lab.local.log:
[be[lab.local]] [sdap_select_principal_from_keytab_sync] (0x0020):
  Failed to get principal from keytab (sss_atomic_read_s() failed),
  see ldap_child.log for details.

[be[lab.local]] [ipa_set_sdap_options] (0x0040):
  Cannot set the SASL-related options

[be[lab.local]] [ipa_init_id_ctx] (0x0020):
  Unable to init id context [5]: Input/output error

[be[lab.local]] [sssm_ipa_init] (0x0020):
  Unable to init IPA ID context [5]: Input/output error

[be[lab.local]] [dp_module_run_constructor] (0x0010):
  Module [ipa] constructor failed [5]: Input/output error

[be[lab.local]] [dp_load_targets] (0x0020):
  Unable to load target [id] [80]: Accessing a corrupted shared library.
```

Error chain: keytab read failure → SASL config failure → IPA module crash →
SSSD backend crash → monitor kills SSSD after startup timeout.

SSSD was trying to read `k8s-master1.lab.local@LAB.LOCAL` from
`/etc/krb5.keytab` and got an I/O error on `sss_atomic_read_s()`.

# Step 3: Check the keytab file
```
klist -k /etc/krb5.keytab
Keytab name: FILE:/etc/krb5.keytab
KVNO Principal
---- --------------------------------------------------------------------------
   1 host/k8s-master1.lab.local@LAB.LOCAL
   1 host/k8s-master1.lab.local@LAB.LOCAL
   1 host/k8s-master1.lab.local@LAB.LOCAL
   1 host/k8s-master1.lab.local@LAB.LOCAL
```

Keytab file is intact — 4 entries present, correct principal. The file itself
was NOT corrupted. The I/O error at boot was likely transient — either the
filesystem wasn't fully ready when SSSD tried to read the keytab during early
boot, or the SSSD cache database (LDB files) was in a bad state from the
unclean shutdown sequence.

# Step 4: Monitor timeout
```
[sssd] [services_startup_timeout] (0x0020): Providers did not start in time!
[sssd] [monitor_quit] (0x3f7c0): Terminating [lab.local][1024]
[sssd] [monitor_quit] (0x3f7c0): Child [lab.local] terminated with a signal
```

The IPA backend crashed before registering with the monitor. Monitor waited
for startup timeout then killed the process. SSSD did not retry — it stayed
in `failed` state permanently.

_____________________________________________________________________

[Final Root Cause]
NOT FULLY IDENTIFIED. The keytab file was intact but SSSD failed to read it
during boot after the backup incident shutdown. Two possible causes:

1. Stale SSSD cache: The LDB cache files in /var/lib/sss/db/ may have been
   in a dirty state from the non-graceful VM suspend during vzdump backup.
   SSSD opened the cache, then failed when trying to read the keytab in the
   same init sequence.

2. Boot timing: SSSD started early in the boot sequence (PID 1016) while
   the filesystem or IPA server may not have been fully available. The
   `sss_atomic_read_s()` failure suggests a low-level read issue that
   resolved itself later — a simple restart 12 hours later worked fine.

The keytab was NOT regenerated — same file, same entries. Only action was
`systemctl restart sssd`. This confirms the file was always valid; the
failure was in SSSD's ability to read it at that specific boot moment.

_____________________________________________________________________

[Final Solution]
Workaround: restarted SSSD manually.

```bash
systemctl restart sssd
```

SSSD started cleanly, GSSAPI authentication succeeded:
```
sssd_be[474569]: GSSAPI client step 1
sssd_be[474569]: GSSAPI client step 1
sssd_be[474569]: GSSAPI client step 1
sssd_be[474569]: GSSAPI client step 2
```

Domain user login restored. `id k8s_admin` works. SSH login works.

No permanent fix applied — root cause of the boot-time read failure is not
identified. If this recurs, potential fixes:
1. Add SSSD restart to a post-boot script or timer
2. Add `Restart=on-failure` and `RestartSec=30s` to sssd.service override
   (give filesystem time to settle before retry)
3. Clear SSSD cache on boot if corruption detected:
   `sss_cache -E` or remove `/var/lib/sss/db/*.ldb`

Verified: Yes — SSSD running, domain users can authenticate, cluster healthy
(all 6 nodes reporting in kubectl top).

_____________________________________________________________________

[Risk Level] LOW-MEDIUM — SSSD failure only affects domain user logins, not
K8s cluster operations (which use certificates, not SSSD). But 12 hours of
silent failure without alerting is a monitoring gap.

_____________________________________________________________________

[References]
- Parent: TS-PVE-015 (Prod thermal shutdown during backup — same incident chain)
- Related: TS-IDN-001 (LXC Kerberos keyring auth failure — similar keytab/SSSD pattern)
- Related: TS-IDN-008 (Keytab preauthentication failed — keytab issues)
- Related: TS-PVE-015 (Dev crash during backup — same backup suspend trigger)
