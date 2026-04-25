# Linux Troubleshooting Cases

Documentation of OS-level issues encountered on Rocky Linux and LXC containers.

---

## Cases

| # | File | Issue | Root Cause |
|---|------|-------|------------|
| 1 | [rocky-linux-dnf-metadata-error](1-rocky-linux-dnf-metadata-error.md) | DNF fails with XML parsing error | Mirrorlist returns bad mirrors, use direct baseurl |
| 2 | [lxc-chronyd-adjtimex-failure](2-lxc-chronyd-adjtimex-failure.md) | Chronyd fails with "adjtimex: Operation not permitted" | LXC lacks CAP_SYS_TIME, skip chronyd on LXC |
| 3 | [linux-nodes-dns-fallback](3-linux-nodes-dns-fallback.md) | SSSD overwrites fallback DNS on IPA outage | zzz-ipa.conf overwrites resolv.conf |
| 4 | [cloud-init-etc-hosts-ownership](4-cloud-init-etc-hosts-ownership.md) | cloud-init wipes /etc/hosts on reboot | cloud-init manages_etc_hosts default behavior |

---

## Quick Reference

### Rocky Linux DNF Issues
- **Case 1:** Disable mirrorlist, use direct HTTPS baseurl to dl.rockylinux.org

### LXC Container Limitations
- **Case 2:** LXC can't run chronyd → skip in Ansible with `when: ansible_virtualization_type != "lxc"`

---

## Related Cases in Other Folders

Several LXC-related cases were moved to **identity/** folder since they're FreeIPA-specific:

| Case | Folder | Topic |
|------|--------|-------|
| TS-IDN-001 | identity/ | LXC Kerberos keyring failure |
| TS-IDN-006 | identity/ | FreeIPA UID range for LXC |
| TS-IDN-007 | identity/ | LXC initgroups error |
| TS-IDN-008 | identity/ | FreeIPA client NTP skip on LXC |

Crontab case moved to **proxmox/** folder:

| Case | Folder | Topic |
|------|--------|-------|
| TS-PVE-007 | proxmox/ | Crontab overwrite recovery |

---

## Environment

- **OS:** Rocky Linux 10.1
- **Containers:** LXC unprivileged on Proxmox
