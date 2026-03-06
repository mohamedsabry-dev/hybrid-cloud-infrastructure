# Troubleshooting Cases Index

Documentation of issues encountered and resolved during infrastructure setup.

---

## LXC Container Issues

| ID | Title | Summary |
|----|-------|---------|
| [TS-001](TS-001_LXC_Kerberos_Keyring_Auth_Failure.md) | Kerberos Keyring Auth Failure | Password auth fails on LXC due to kernel keyring UID mapping |
| [TS-002](TS-002_LXC_NTP_Configuration_Disabled.md) | NTP Configuration Disabled | LXC containers inherit time from host, can't run chronyd |
| [TS-005](TS-005_LXC_UID_Mapping_initgroups_Error.md) | UID Mapping initgroups Error | FreeIPA default UIDs outside LXC mapped range |

---

## FreeIPA DNS Issues

| ID | Title | Summary |
|----|-------|---------|
| [TS-003](TS-003_FreeIPA_DNS_Configuration_Issues.md) | DNS Configuration Issues | DNS recursion denied + forwarders syntax error |

---

## SSH/Authentication Issues

| ID | Title | Summary |
|----|-------|---------|
| [TS-004](TS-004_VM_SSH_Permission_Denied_Cloud_Init.md) | VM SSH Permission Denied | Cloud-init disables password auth on VMs |
| [TS-006](TS-006_Kerberos_GSSAPI_Requires_Hostnames.md) | Kerberos Requires Hostnames | GSSAPI auth fails when using IP addresses |

---

## FreeIPA Configuration

| ID | Title | Summary |
|----|-------|---------|
| [TS-007](TS-007_FreeIPA_Configuration_Requirements.md) | Configuration Requirements | cospriority, server SSSD, UID_MAX gotchas |

---

## Quick Reference

### Common Patterns

| Symptom | Likely Cause | TS Case |
|---------|--------------|---------|
| Password keeps prompting on LXC | Keyring UID mapping | TS-001 |
| `initgroups: Invalid argument` | FreeIPA UID out of range | TS-005 |
| `Permission denied (publickey,gssapi...)` on VM | Cloud-init disabled password | TS-004 |
| SSH with IP fails, hostname works | Kerberos needs FQDN | TS-006 |
| DNS recursion REFUSED | BIND recursion not allowed | TS-003 |
| Chronyd fails on LXC | LXC can't manage time | TS-002 |
| `cospriority is required` | Missing password policy priority | TS-007 |
| Sudo doesn't work on FreeIPA server | Server != client | TS-007 |

### Key Fixes

```bash
# TS-001: Fix LXC Kerberos keyring
# Add to sssd.conf: krb5_ccache_template = FILE:/tmp/krb5cc_%U

# TS-004: Enable password auth on VMs
ansible k8s -m replace -a "path=/etc/ssh/sshd_config.d/50-cloud-init.conf regexp='PasswordAuthentication no' replace='PasswordAuthentication yes'" --become

# TS-006: Use GSSAPI with kinit
kinit super_bot && ssh super_bot@hostname.lab.local
```

---

## Contributing

When adding new troubleshooting cases:

1. Use format: `TS-XXX_Short_Title.md`
2. Include: Symptom, Root Cause, Solution, Simple Explanation
3. Update this README index
