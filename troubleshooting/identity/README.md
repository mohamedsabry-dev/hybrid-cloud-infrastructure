# Identity Troubleshooting Cases

Documentation of FreeIPA, Kerberos, and SSSD issues encountered in the hybrid cloud infrastructure.

---

## Cases

| # | File | Issue | Root Cause |
|---|------|-------|------------|
| 1 | [lxc-kerberos-keyring-auth-failure](1-lxc-kerberos-keyring-auth-failure.md) | Password auth fails on LXC, GSSAPI works | Kernel keyring UID mismatch in LXC namespace |
| 2 | [freeipa-dns-configuration-issues](2-freeipa-dns-configuration-issues.md) | Clients can't resolve external domains | DNS forwarders not applied + recursion denied |
| 3 | [kerberos-gssapi-requires-hostnames](3-kerberos-gssapi-requires-hostnames.md) | SSH works with hostname, fails with IP | Kerberos principals tied to FQDNs not IPs |
| 4 | [freeipa-password-policy-cospriority](4-freeipa-password-policy-cospriority.md) | Group password policy creation fails | cospriority required for group-based policies |
| 5 | [freeipa-server-sssd-sudo](5-freeipa-server-sssd-sudo.md) | Sudo rules work on clients not server | FreeIPA server doesn't apply its own SSSD rules |
| 6 | [freeipa-lxc-uid-range-investigation](6-freeipa-lxc-uid-range-investigation.md) | initgroups fails, UID range errors | FreeIPA UIDs must be 60001-65500 for LXC |
| 7 | [freeipa-client-ntp-lxc-skip](7-freeipa-client-ntp-lxc-skip.md) | NTP config fails on LXC during enrollment | LXC inherits time from host, skip NTP config |
| 8 | [keytab-preauthentication-failed](8-keytab-preauthentication-failed.md) | Keytab authentication fails | Preauthentication error - keytab issues |

---

## Quick Reference

### LXC-Specific Issues

| Case | Problem | Solution |
|------|---------|----------|
| 1 | Keyring UID mismatch | `krb5_ccache_template = FILE:/tmp/krb5cc_%U` |
| 6 | UID out of mapped range | Set `ipaserver_idstart: 60001`, `ipaserver_idmax: 65500` |
| 7 | NTP can't run in LXC | Set `ipaclient_no_ntp: true` |

### FreeIPA Server Configuration

| Case | Problem | Solution |
|------|---------|----------|
| 2 | External DNS fails | Add forwarders + allow-recursion for 10.0.0.0/8 |
| 4 | Policy creation fails | Add `cospriority` parameter |
| 5 | Sudo not working on server | Use root directly for FreeIPA server |

### Kerberos/Authentication

| Case | Problem | Solution |
|------|---------|----------|
| 3 | IP-based SSH fails | Use FQDNs in inventory, not IPs |
| 8 | Keytab auth fails | Check keytab validity, regenerate if needed |

---

## Environment

- **FreeIPA Server:** freeipa.lab.local
- **Domain:** lab.local
- **Realm:** LAB.LOCAL
- **UID Range:** 60001-65500 (LXC compatible)

