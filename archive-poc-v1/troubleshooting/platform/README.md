# Platform — 13 cases

vCenter, ESXi, FreeIPA, and Windows host issues from the PoC v1 era.

[reference/](reference/) has 2 guides

| # | File | What Happened |
|---|------|---------------|
| 01 | [vcenter-install-hang](01-vcenter-installation-stage2-hang.md) | vCenter installation stuck Stage 2 — DNS resolution failure |
| 02 | [vcenter-sso](02-vcenter-authentication-error-sso.md) | SSO authentication failing — alias whitelist |
| 03 | [lifecycle-manager-depot](03-vcenter-lifecycle-manager-depot-error.md) | Deprecated update repository URLs |
| 05 | [cert-manager](05-vcenter-certificate-manager-replace-failed.md) | Certificate replacement failed — service health issues |
| 06 | [api-ssl](06-vcenter-api-ssl-error-after-root-ca.md) | API SSL verification fails — trust store out of sync with new CA |
| 08 | [windows-sleep-network](08-windows-host-sleep-network-break.md) | ESXi uplink down after laptop sleep/wake — all VMs lose network |
| 10 | [vapp-config](10-vcenter8-vapp-config-not-persisting.md) | vApp config resets on restart — database transaction bug |
| 11 | [freeipa-clock-skew](11-freeipa-time-sync-clock-skew.md) | VMware Tools time sync fighting chrony — cascading Kerberos auth failures |
| 12 | [sssd-cache](12-freeipa-sssd-cache-not-updating.md) | Sudo rule changes not reflecting in SSSD cache |
| 13 | [vcenter-backup-ip-change](13-vcenter-backup-failure-after-ip-change.md) | Backup fails after IP/hostname change — chain metadata references old values |
| 14 | [lifecycle-plugin](14-vsphere-lifecycle-manager-plugin-download-error.md) | Plugin download fails after IP/certificate change |
| 15 | [firewall-interface](15-vcenter-firewall-invalid-interface-error.md) | Firewall GUI fails on deleted NIC references |
| 16 | [esxi-autoprotect](16-esxi-master-autoprotect-snapshot-performance-degradation.md) | 12 accumulated snapshots — 6min of 1-8s disk latency |

---

## Related

- [Troubleshooting overview](../README.md)
- [FreeIPA documentation](../../docs/identity/)
