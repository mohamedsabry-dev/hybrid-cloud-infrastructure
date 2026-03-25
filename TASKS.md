# Tasks

## Backup

| Task | Status | Notes |
|------|--------|-------|
| Backup load test — monitor CPU, RAM, storage during backup run, record observations | ✅ Done | Results in `proxmox/backup/workload_backup/drafted_test_raw_output.txt`; analysis in `test-performance-plan.md` and `backup-performance-test-explained.txt` |
| Set up Raft backup directory | ⬜ Pending | Vault Raft storage backend snapshot directory not yet configured |
| Backup Proxmox config itself | ✅ Done | Script at `proxmox/backup/proxmox_backup/backup-proxmox-config.sh`; schedule defined in the cron entry added by that script |
| Backup Raft cluster config | ⬜ Pending | Vault Raft periodic snapshot/restore procedure not yet documented or automated |
| Save network device configs (ER605 + switch) to NAS | ✅ Done | Saved to NAS shared backup dir (gitignored locally) |

## Automation / Consolidation

| Task | Status | Notes |
|------|--------|-------|
| Consolidation phase — refactor automation so each workflow sets up its own compute, joins FreeIPA, and runs via local runner + keytab | ⬜ Pending | Design notes in `automation_migration_change.txt`; to be done in parallel with K8s phase |
