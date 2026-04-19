# Golden Templates

Scripts to prepare base VM/LXC images for cloning. Run once (per OS rebuild) to create the golden templates that Terraform then clones from.

> **Design notes & reasoning** — for why each package is in the list, why `firewalld` is installed-but-disabled by default, why debugging tools are shipped on every node, and how these scripts grew iteratively, see [`DESIGN.md`](DESIGN.md).

## Scripts

| Script | Target | Usage |
|--------|--------|-------|
| `golden-vm-setup.sh` | QEMU VM | Run inside VM after OS install, before converting to template |
| `golden-lxc-setup.sh` | LXC Container | Run inside container, before vzdump to create template |

## golden-vm-setup.sh (QEMU VMs)

**When to use:** After manual Rocky Linux installation on a new VM.

**What it does:**
1. System update + EPEL repo
2. Install packages:
   - `qemu-guest-agent`, `cloud-init` (Proxmox/Terraform integration)
   - `curl`, `wget`, `vim`, `htop`, `git`, `tree`, `jq`
   - `openssh-server/clients`, `audit`, `rsyslog`
   - `net-tools`, `traceroute`, `bind-utils`, `tcpdump`, `nmap-ncat`
   - `ipa-client` (package only, not configured)
3. Create `gandalf` break-glass user (locked, password set via Ansible)
4. Configure services:
   - Enable: qemu-guest-agent, sshd, cloud-init, rsyslog, auditd
   - Disable: firewalld (enable via Ansible if needed)
   - SSH: root login with keys only (prohibit-password)
   - Serial console: enabled for `qm terminal` access
5. Cleanup (on confirmation):
   - Clear machine-id, SSH host keys, authorized_keys
   - Clear network config, logs, temp files, history
   - Reset cloud-init state

**Final steps (manual):**
1. Remove CD-ROM
2. Set boot order to disk only
3. Convert to template in Proxmox UI

## golden-lxc-setup.sh (LXC Containers)

**When to use:** After creating a new LXC from upstream Rocky template.

**What it does:**
1. System update + EPEL repo
2. Install packages:
   - `curl`, `wget`, `vim`, `htop`, `git`, `tree`, `jq`
   - `openssh-server/clients`, `rsyslog`, `firewalld`
   - `net-tools`, `traceroute`, `bind-utils`, `tcpdump`, `nmap-ncat`
   - `ipa-client` (package only, not configured)
3. Create `gandalf` break-glass user (locked)
4. Configure services:
   - Enable: sshd, rsyslog
   - Disable: firewalld
   - SSH: root login enabled
5. Cleanup:
   - Clear network config, SSH host keys
   - Clear machine-id, logs, cache, history

**Final steps (manual):**
```bash
# Stop container
pct stop 9001

# Create vzdump backup
vzdump 9001 --compress gzip --storage local --mode stop

# Move to template cache
mv /var/lib/vz/dump/vzdump-lxc-9001-*.tar.gz \
   /mnt/pve/nas-iso/template/cache/rocky-9-lxc-golden.tar.gz

# Verify
pveam list nas-iso
```

## Key Differences

| Feature | VM | LXC |
|---------|----|----|
| qemu-guest-agent | Yes | No (not a VM) |
| cloud-init | Yes (TF uses for IP/keys) | No |
| auditd | Yes | No (host audits) |
| Serial console | Yes (qm terminal) | No (pct enter) |
| Template creation | Proxmox UI convert | vzdump + move to cache |

## Notes

- **IPA client**: Package installed but NOT enrolled. Ansible enrolls each cloned VM/LXC
- **gandalf user**: Emergency access, password set via Ansible from AWS Secrets Manager
- **firewalld**: Installed but disabled. Ansible enables with proper rules if needed
- **SSH keys**: Cleared during cleanup. Terraform injects per-VM keys via cloud-init (VMs) or Proxmox API (LXCs)
