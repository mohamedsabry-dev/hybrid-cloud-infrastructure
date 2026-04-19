# Proxmox Backup & Snapshot Guide

## Quick Reference

| Feature | Storage | Managed By |
|---------|---------|------------|
| Backups (vzdump) | NFS (NAS) | Terraform + PVE GUI |
| Snapshots | local-lvm | PVE GUI (manual) |

---

## Backups

### Schedule
```
thu,sat 21:00
```

| Day | Purpose |
|-----|---------|
| Thursday 9 PM | Pre-change backup (before Fri/Sat work) |
| Saturday 9 PM | Post-change backup (captures weekend work) |

### Configuration

| Setting | Value |
|---------|-------|
| Schedule | `thu,sat 21:00` |
| Mode | `snapshot` |
| Compression | `ZSTD` |
| Storage | `nas-dev-data` / `nas-prod-data` |
| Selection | All |
| Retention | (empty - uses storage config) |
| Repeat missed | Yes |

### Setup (One-Time)
```
Datacenter → Backup → Add
  Schedule:     thu,sat 21:00
  Mode:         snapshot
  Compression:  ZSTD
  Storage:      nas-prod-data
  Selection:    All
  Retention:    (leave empty - uses Terraform config)
  Advanced:     Check "Repeat missed"
```

### Observed Backup Performance (Prod)

| Resource | Type | Disk Size | Archive Size | Time |
|----------|------|-----------|--------------|------|
| FreeIPA | VM | 50GB | 1.63GB | 1:17 |
| K8s Master | VM | 25GB | ~1.4GB | ~26s |
| K8s Worker | VM | 105GB | 1.06GB | 2:46 |
| LXC (Vault, Ansible, etc.) | LXC | ~15GB | ~300MB | ~1 min |

> **Note:** 90-97% sparse (empty space) = efficient compression

### Backup Behavior

| Phase | Duration | What Happens |
|-------|----------|--------------|
| `fs-freeze` | 2-5 sec | Filesystem frozen, SSH may drop |
| Snapshot | instant | LVM snapshot created |
| `fs-thaw` | instant | Filesystem unfrozen |
| Data transfer | minutes | VM fully running, data copied to NAS |

> **Observation:** Brief SSH disconnection during `fs-freeze` is normal. CPU spike (~70%) during backup due to ZSTD compression. This is why backups run at 21:00 (low activity).

### Retention Strategy

**Current: `keep_last = 5`.** Story behind the number:

I started on `keep_last = 2` — one backup Thursday (pre-weekend) and one Saturday (post-weekend). The thinking was minimal footprint: the Thursday copy is a rollback point if Fri/Sat changes break something, and the Saturday copy captures the weekend work. That's the pattern in the diagram below:

```
Mon─Tue─Wed─Thu─────────Fri─Sat─────────Sun
              ↓             ↓
        [BACKUP 1]    [BACKUP 2]
        pre-change    post-change
```

I moved it to `keep_last = 5` after realising how much I actually rely on backups inside the k8s layer — the incident captured in [`troubleshooting/terraform/10-cloud-init-ssh-host-key-regeneration.md`](../../../troubleshooting/terraform/10-cloud-init-ssh-host-key-regeneration.md) is a good example of why: a change made on day 1 doesn't necessarily show up as broken until day 3 or 4, and by then the 2-backup window is already gone. With 5, if I hit an issue on day 5 that turns out to be rooted in an edit from day 1, I can still restore a dummy VM from that day's backup and diff the config / behaviour side-by-side, or do a full restore if I need to.

NAS capacity is not the constraint — there's plenty of storage. The real constraint is how far back in time I can look when an issue turns out to be rooted deeper than I thought.

### Terraform Config
Storage retention managed via Terraform:
```hcl
# terraform/dev/proxmox/storage/nas/variables.tf
variable "nas_data" {
  default = {
    id        = "nas-dev-data"
    content   = ["images", "rootdir", "backup"]
    keep_last = 5
  }
}
```

### Email Notifications

To receive backup status emails, configure Gmail SMTP relay on Proxmox:

```bash
# Run the setup script
./proxmox/bootstrap_proxmox/mail-config.sh
```

Or manually:
```bash
apt install libsasl2-modules -y
echo "[smtp.gmail.com]:587 your-email@gmail.com:APP_PASSWORD" > /etc/postfix/sasl_passwd
chmod 600 /etc/postfix/sasl_passwd
postmap /etc/postfix/sasl_passwd
postconf -e "relayhost = [smtp.gmail.com]:587"
postconf -e "smtp_tls_security_level = encrypt"
postconf -e "smtp_sasl_auth_enable = yes"
postconf -e "smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd"
postconf -e "smtp_sasl_security_options = noanonymous"
systemctl restart postfix
```

> **Requires:** Gmail App Password (Google Account → Security → App passwords)

See: [scripts/mail-config.sh](scripts/mail-config.sh) | [mail-config.md](mail-config.md)

---

## Snapshots

### Storage Requirements

| Storage | Snapshots | Use For |
|---------|-----------|---------|
| local-lvm | Yes | OS disks, mount points |
| ZFS | Yes | OS disks, mount points |
| NFS | No | Backups, ISOs, templates |

### LXC Snapshot Limitation
LXC containers with NFS mount points **cannot take snapshots**.

**Fix:** Move mount points to local-lvm:
```bash
pct stop <ctid>
pct move-volume <ctid> mp0 local-lvm
pct start <ctid>
pct set <ctid> --delete unused0
```

See: [troubleshooting/proxmox/16-proxmox-lxc-snapshot-nfs-mount.md](../troubleshooting/proxmox/16-proxmox-lxc-snapshot-nfs-mount.md)

### When to Snapshot
Take snapshots **before risky operations**:
- Major configuration changes
- Vault/K8s cluster setup
- OS/kernel upgrades
- Ansible playbook runs

### Naming Convention
```
pre-<operation>-YYYY-MM-DD
Example: pre-vault-setup-2026-03-08
```

---

## Backups vs Snapshots

| | Backups | Snapshots |
|---|---------|-----------|
| Purpose | Disaster recovery | Quick rollback |
| Storage | External (NAS) | Local (same disk) |
| Speed | Minutes | Instant |
| Schedule | Automated (thu,sat 21:00) | Manual, event-driven |
| Survives disk failure | Yes | No |

**Best Practice:** Use both. Snapshots for quick rollback during changes, backups for disaster recovery.
