# Storage — 7 cases

VMware snapshots, NAS, and disk issues from the PoC v1 era.

[reference/](reference/) has 3 guides

| # | File | What Happened |
|---|------|---------------|
| 01 | [vmdk-snapshot-corruption](01-vmdk-snapshot-corruption.md) | Snapshot chain breakage from cross-partition vDisks |
| 02 | [nas-snapshot-sizing](02-nas-snapshot-sizing-failure.md) | 980GB thick disk, 450GB free — snapshot failed, NAS VM entered maintenance mode |
| 03 | [disk-race-condition](03-disk-race-condition-disaster.md) | /dev/sdX names swapped on reboot — ALL VMs inaccessible |
| 05 | [nas-memory-starvation](05-nas-memory-starvation.md) | NAS RAM cut while doubling VMs — kernel soft lockups, 31-47s CPU stalls |
| 07 | [snapshot-chain-corruption](07-vmware-snapshot-chain-corruption.md) | Parent-child VMDK links broken from cross-drive snapshots |
| 09 | [veeam-aap-loop-device](09-application-aware-backup-loop-device-errors.md) | Loop device I/O errors during Veeam application-aware backup |
| 10 | [snapshot-corruption-sleep](10-snapshot-chain-corruption-sleep-mode.md) | Laptop slept mid-Veeam backup — thin disk inflated 98GB → 1TB |

---

## Related

- [Troubleshooting overview](../README.md)
- [Storage documentation](../../docs/storage/)
- [Backup documentation](../../docs/backup/)
