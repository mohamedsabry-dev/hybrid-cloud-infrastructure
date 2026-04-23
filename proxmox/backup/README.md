# Backup

Backup strategy for the Proxmox layer. Split into two independent pieces:

1. **Proxmox host config** — script-based tarball of all the files needed to rebuild a Proxmox host from a fresh install (`/etc/pve`, network, storage, grub, cron, systemd, …). Runs from cron on each host, drops on the NAS, keeps last 5.
2. **Workload backup (VM/LXC)** — native Proxmox `vzdump` to NFS on the NAS, `snapshot` mode, ZSTD, all guests per host, `repeat-missed=1`, keeps last 5.

Deliberately **not** running Proxmox Backup Server (PBS) — the reasoning is in [`DESIGN.md`](DESIGN.md) along with the story behind the frequency + retention numbers.

> **Design notes & reasoning** — for why PBS isn't used, the disaster-recovery path it's replaced with, the 2/week → 3-4/week schedule evolution, and the `keep_last` 2 → 5 retention story (tied to a real TS case), see [`DESIGN.md`](DESIGN.md).

---

## Layout

```
backup/
├── README.md                                        # This file
├── DESIGN.md                                        # The story
│
├── proxmox_backup/                                  # Host config backup
│   └── backup-proxmox-config.sh                     # Runs from cron, tars /etc/pve + essentials to NAS, keeps last 5
│
└── workload_backup/                                 # VM / LXC vzdump reference
    ├── backup-snapshot.md                           # Main guide: schedule, modes, retention, performance, snapshots
    ├── backup_config_guide.txt                      # /etc/pve/jobs.cfg layout + PVE web-UI config walkthrough
    ├── test-performance-plan.md                     # Performance test plan
    └── backup-performance-test-explained.txt        # Performance test results + commentary
```

## Quick reference

| What | Runs on | Target | Frequency | Retention |
|------|---------|--------|-----------|-----------|
| Config tarball (`backup-proxmox-config.sh`) | Each Proxmox host (cron) | NAS `Backups` NFS share (via `nas-backups` storage) | Thu, Sat 21:00 (matches vzdump) | last 5 per host |
| vzdump (VM + LXC) | Each Proxmox host (PVE job) | NAS `nas-{env}-data` NFS share | Thu, Sat 21:00 — planned move to every 2 days | `keep_last=5` per node |

The `keep_last = 5` is deployed via Terraform in `terraform/*/proxmox/storage/nas/variables.tf` for both `nas_data` and `backups`.

## Disaster recovery path (config-backup + vzdump combined)

If a Proxmox host's disk dies:

1. Reinstall Proxmox VE on replacement hardware.
2. Run [`../bootstrap_proxmox/bootstrap.sh`](../bootstrap_proxmox/bootstrap.sh) + [`../bootstrap_proxmox/network-setup.sh`](../bootstrap_proxmox/network-setup.sh).
3. Mount the NAS, extract the most recent `proxmox-config-<host>-*.tar.gz` from `/mnt/pve/nas-backups/dump/`, apply the configs (see restore notes inside the script).
4. Restore all workloads from their `vzdump` archives on the NAS.
5. Rotate the Proxmox API token and update it in AWS Secrets Manager + Vault.

Full reasoning for why this replaces PBS is in [`DESIGN.md`](DESIGN.md).

## Notes on filenames

Naming across this folder is inconsistent — `backup_config_guide.txt` uses underscores while everything else uses hyphens, and the two performance-test files aren't clearly paired by name. Kept as-is to avoid breaking a reference in `deployment-docs/proxmox-setup-guide.txt`. Safe to normalise in a later pass if desired.
