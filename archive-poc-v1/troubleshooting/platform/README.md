# Platform Troubleshooting

vCenter, ESXi, FreeIPA, and Windows host issues.

## Cases (15)

### vCenter Issues
| Case | Issue | Root Cause |
|------|-------|------------|
| 01 | Installation Stage 2 Hang | DNS resolution failure |
| 02 | SSO Authentication Error | Alias whitelist configuration |
| 03 | Lifecycle Manager Depot Error | Deprecated update URLs |
| 04 | Certificate Browser Errors | Cache and trust store |
| 05 | Certificate Manager Failures | Service health and disk space |
| 06 | API SSL Verification Errors | Python/PowerCLI trust stores |
| 10 | vApp Config Not Persisting | Database transaction bug |
| 13 | Backup Failure After IP Change | DNS cache issues |
| 14 | Lifecycle Manager Plugin Download | Network timeout |
| 15 | Firewall Invalid Interface | Configuration corruption |
| 16 | Autoprotect Snapshot Performance | Excessive snapshot creation |

### Windows Host Issues
| Case | Issue | Root Cause |
|------|-------|------------|
| 08 | Sleep Mode Network Failure | ESXi uplink down after sleep/wake |
| 09 | NAT vs Bridged Networking | Architecture comparison |

### FreeIPA Issues
| Case | Issue | Root Cause |
|------|-------|------------|
| 11 | Time Sync Clock Skew | VMware Tools time sync conflict |
| 12 | SSSD Cache Not Updating | HBAC/sudo rule caching |

## Related

- [Troubleshooting overview](../README.md)
- [FreeIPA documentation](../../docs/identity/)
