# Storage Troubleshooting

VMware snapshots, NAS, and disk issues.

## Cases (10)

| Case | Issue | Root Cause |
|------|-------|------------|
| 01 | VMDK Snapshot Corruption | Snapshot chain breakage |
| 02 | NAS Snapshot Sizing Failure | Insufficient space |
| 03 | Disk Race Condition Disaster | /dev/sdX vs UUID mounting |
| 04 | Thick to Thin Conversion | Provisioning type conversion |
| 05 | NAS Memory Starvation | I/O performance degradation |
| 06 | NAS Backup Strategy Optimization | Backup job optimization |
| 07 | VMware Snapshot Chain Corruption | Parent VMDK link breakage |
| 08 | Thick Provisioned Snapshot Size | Massive snapshots from thick disks |
| 09 | Application-Aware Backup Errors | Veeam AAP causing I/O errors |
| 10 | Snapshot Chain Corruption Sleep | Laptop sleep during I/O |

## Key Lessons

- Always use UUID mounting, never /dev/sdX
- Monitor snapshot chain depth
- Test Veeam application-aware backups before production
- Never sleep host during VM I/O operations

## Related

- [Troubleshooting overview](../README.md)
- [Storage documentation](../../docs/storage/)
- [Backup documentation](../../docs/backup/)
