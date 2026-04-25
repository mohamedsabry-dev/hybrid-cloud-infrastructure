# Proxmox VE - Setup Guide

Note: If you face issues during deployment, check the troubleshooting/ folder
for the related technology section. Most common issues have been documented there.
Relevant folders: troubleshooting/proxmox/, troubleshooting/linux/

For more details, see: proxmox/README.md and proxmox/bootstrap_proxmox/README.md

---

## Overview

This guide covers the setup of Proxmox VE servers on laptop hardware with a
3-port network design (WiFi management, service VLANs, storage network).

IMPORTANT: Proxmox setup must be completed BEFORE AWS Secrets and GitHub Setup,
as the API token generated during bootstrap is stored in AWS Secrets Manager.

---

### A note for anyone implementing this

The specifics below — "Proxmox on laptops", three *physical* NICs per host
(built-in WiFi + two USB-Ethernet adapters), WiFi used as the management
plane, 100M forced on the service port — reflect MY hardware constraints and
learning goals, not Proxmox best practice.

If you have rack servers with multiple built-in NICs, the "3-plane
separation with USB-ETH" part of this guide doesn't apply — you'd wire
management / service / storage to 3 on-board ports and skip the USB
adapters entirely. Likewise, "management over WiFi" is a consequence of the
laptop form factor (no second built-in wired port), not a recommendation.

For the full reasoning — why Proxmox on laptops, why two physical hosts
instead of one nested, why the 3-plane NIC pattern, why the bootstrap
scripts grew from a manual-first run, why OS disks stay on local Proxmox
storage while workloads run on NAS — see the sibling design docs:

  - proxmox/DESIGN.md              (layer-level story)
  - proxmox/bootstrap_proxmox/DESIGN.md   (bootstrap-script origin + Terraform-user design)
  - proxmox/storage/DESIGN.md      (why OS-on-local, NAS-for-data split + VLAN 40 worker NIC)
  - proxmox/golden_templates/DESIGN.md    (what goes in golden vs Ansible)
  - proxmox/backup/DESIGN.md       (why no PBS, config + vzdump backup split, retention evolution)
  - proxmox/disaster_recovery/DESIGN.md   (host-layer runbooks + prevention scripts vs platform chaos tests)

---

## Server Details

| Environment | Hostname              | Management IP | Storage IP   | API URL                         |
|-------------|-----------------------|---------------|--------------|----------------------------------|
| PROD        | pve-prod.lab.local    | 10.0.5.100    | 10.0.40.100  | https://pve-prod.lab.local:8006 |
| DEV         | pve-dev.lab.local     | 10.0.5.110    | 10.0.40.110  | https://pve-dev.lab.local:8006  |

---

## Network Architecture (3-plane design, laptop form factor)

```
Laptop Hardware
+--------------------+--------------------+--------------------+
|      WiFi          |       svc0         |       stor0        |
|   (wlp1s0/wlp4s0)  | (USB-Ethernet A)   |  (USB-Ethernet C)  |
+--------------------+--------------------+--------------------+
          |                     |                     |
          v                     v                     v
   VLAN 5 (Mgmt)         VLANs 60-65 (Dev)      VLAN 40 (Storage)
   10.0.5.x              VLANs 50-55 (Prod)     10.0.40.x
                         via vmbr0              via vmbr1
```

Three *physical* NICs per host, one per traffic plane. The two Ethernet
adapters are USB-attached (one Type-A, one Type-C) — the laptop has only
one built-in wired port, so USB adapters are what makes the plane split
possible. See proxmox/DESIGN.md → "Three traffic planes, physically
separated" for the full reasoning.

### Port Naming (During Installation)

During Proxmox installation, name each interface:
- USB-Ethernet (Type-A) → svc0 (service trunk, VLANs 50-55 prod / 60-65 dev)
- USB-Ethernet (Type-C) → stor0 (storage plane, VLAN 40)
- WiFi → keep original name (e.g. wlp1s0 on dev, wlp4s0 on prod)

### Interface Configuration

| Interface | Bridge | VLANs     | Purpose                          |
|-----------|--------|-----------|----------------------------------|
| WiFi      | -      | 5         | Management (10.0.5.x)            |
| svc0      | vmbr0  | 60-65 (Dev) / 50-55 (Prod) | VM service networks |
| stor0     | vmbr1  | 40        | NAS storage access               |

---

## Phase 1: Proxmox Installation

### 1.1 Boot from ISO

Boot from: proxmox-ve_9.x.iso

During installation:
1. Name interfaces as described above (svc0, stor0, keep WiFi name)
2. Set temporary IP for initial access (any available)
3. Complete installation and reboot

### 1.2 Initial Access

Use any connected ethernet port or temporary network for initial SSH access.

---

## Phase 2: Bootstrap Proxmox

### 2.1 Copy and Run Bootstrap Script

Script Path: proxmox/bootstrap_proxmox/bootstrap.sh

  scp proxmox/bootstrap_proxmox/bootstrap.sh root@<temp-ip>:/tmp/
  ssh root@<temp-ip>
  chmod +x /tmp/bootstrap.sh && /tmp/bootstrap.sh dev   # or prod

### 2.2 What bootstrap.sh Does

- Disables sleep/suspend/hibernate
- Adds fallback DNS (8.8.8.8)
- Disables enterprise repos, enables no-subscription repo
- APT update & upgrade
- Removes subscription nag popup
- Configures Chrony NTP + timezone
- Creates admin user (admin_dev or admin_prod)
- Creates Terraform automation user (tf_dev or tf_prod) with API token

### 2.3 Save API Token

IMPORTANT: Save the API token output from bootstrap.sh.
This token will be stored in AWS Secrets Manager later.

Format: {"token_id":"tf_dev@pve!terraform","token_secret":"xxxxxxxx-xxxx-xxxx-xxxx"}

---

## Phase 3: Network Setup

### 3.1 Copy and Run Network Script

Script Path: proxmox/bootstrap_proxmox/network-setup.sh

IMPORTANT: Run from console or storage network, NOT over WiFi (it will disconnect you).

  scp proxmox/bootstrap_proxmox/network-setup.sh root@<ip>:/tmp/
  ssh root@<ip>
  chmod +x /tmp/network-setup.sh
  WIFI_PASSWORD="xxx" /tmp/network-setup.sh dev   # or prod

### 3.2 What network-setup.sh Does

- Installs wpa_supplicant and wireless-tools
- Configures WiFi for unified_mgmt SSID
- Tests WiFi connectivity
- Configures /etc/network/interfaces:
  - WiFi management interface (VLAN 5)
  - Service VLAN trunk (vmbr0)
  - Storage VLAN interface (vmbr1)
- Updates /etc/hosts
- Regenerates Proxmox SSL certificate

### 3.3 Reboot and Verify

  reboot

After reboot, verify:

  ping 10.0.5.1              # Gateway
  ping 10.0.40.120           # NAS storage
  bridge vlan show           # VLAN configuration

Access Proxmox UI: https://pve-dev.lab.local:8006

---

## Phase 4: NAS Storage Configuration

### 4.1 NAS Details

Device: ASUSTOR FLASHSTOR 6 FS6706T
Management: https://10.0.5.120:8001
Storage IP: 10.0.40.120

### 4.2 Create NFS Shares on NAS (Manual)

Create shares via NAS web interface:

| Share          | NFS Path               | Access                           |
|----------------|------------------------|----------------------------------|
| shared-iso     | /volume1/shared-iso    | 10.0.40.100 + 10.0.40.110        |
| prod-storage   | /volume1/prod-storage  | 10.0.40.100 only                 |
| dev-storage    | /volume1/dev-storage   | 10.0.40.110 only                 |
| Backups        | /volume1/Backups       | 10.0.40.100 + 10.0.40.110        |
| k8s-prod       | /volume1/k8s-prod      | 10.0.40.101-103 (Prod K8s workers) |
| k8s-dev        | /volume1/k8s-dev       | 10.0.40.201-203 (Dev K8s workers)  |

NFS Settings: root Mapping = root (0), Async = Yes

For detailed configuration, see: proxmox/storage/nas-storage-config.md

### 4.3 Configure Proxmox Storage via Terraform

Terraform Path: terraform/dev/proxmox/storage/nas/

GitHub Workflow: .github/workflows/dev-proxmox-storage.yml

Gate Lock: DEV_PROXMOX_STORAGE_NAS_CONFIG

This creates NFS storage mounts in Proxmox:
- nas-iso: ISOs and CT templates
- nas-dev-data: VM images, container rootfs (keep_last=5)
- nas-backups: vzdump backups (keep_last=5)

### 4.4 Verify Storage

  showmount -e 10.0.40.120

Note: Upload ISOs to shared-iso/template/iso/ (not root)

---

## Phase 5: K8s Shared Storage

For Kubernetes persistent volumes, dedicated NFS shares are configured on the NAS:

### 5.1 NFS Shares for K8s

| Share     | NFS Path          | Allowed Clients              | Purpose                    |
|-----------|-------------------|------------------------------|----------------------------|
| k8s-prod  | /volume1/k8s-prod | 10.0.40.101, 102, 103        | Prod K8s PV storage        |
| k8s-dev   | /volume1/k8s-dev  | 10.0.40.201, 202, 203        | Dev K8s PV storage         |

Note: Dev workers use the `.200` range deliberately — wide gap from Prod's
`.100` range so an NFS allowlist typo can't silently cross envs. See
proxmox/storage/DESIGN.md for the IP-range reasoning.

### 5.2 NAS NFS Configuration

On ASUSTOR NAS (https://10.0.5.120:8001):
1. Control Panel → Shared Folders → Create k8s-prod and k8s-dev
2. Control Panel → NFS → Enable NFS, add permissions:
   - Path: /volume1/k8s-prod
   - IP: 10.0.40.101, 10.0.40.102, 10.0.40.103 (or 10.0.40.101-103)
   - Privilege: Read/Write
   - Root Mapping: Map to root (0)
   - Async: Yes
3. Repeat for /volume1/k8s-dev with IPs 10.0.40.201-203

### 5.3 Subdirectory Structure

Create subdirectories for workload separation:
  mkdir -p /volume1/k8s-dev/{monitoring,logging,apps,testing}
  mkdir -p /volume1/k8s-prod/{monitoring,logging,apps,production}

### 5.4 K8s Storage References

- NFS CSI Driver: kubernetes/dev/deployments/infrastructure/storage/
- StorageClass: nfs-csi (dynamic provisioning)
- Troubleshooting: troubleshooting/kubernetes/reference/6-nfs-storage-complete-guide-static-to-dynamic.md

---

## Verification Checklist

- [ ] https://pve-dev.lab.local:8006 accessible
- [ ] WiFi management working (10.0.5.x)
- [ ] Storage network working (ping 10.0.40.120)
- [ ] VLANs configured (bridge vlan show)
- [ ] API token saved for AWS Secrets
- [ ] NFS mounts visible (showmount -e 10.0.40.120)

---

## Summary - File Reference

| Component                | Path                                              |
|--------------------------|---------------------------------------------------|
| Proxmox README           | proxmox/README.md                                 |
| Proxmox layer DESIGN     | proxmox/DESIGN.md                                 |
| Bootstrap README         | proxmox/bootstrap_proxmox/README.md               |
| Bootstrap DESIGN         | proxmox/bootstrap_proxmox/DESIGN.md               |
| Bootstrap Script         | proxmox/bootstrap_proxmox/bootstrap.sh            |
| Network Script           | proxmox/bootstrap_proxmox/network-setup.sh        |
| Storage README           | proxmox/storage/README.md                         |
| Storage DESIGN           | proxmox/storage/DESIGN.md                         |
| NAS Storage Config       | proxmox/storage/nas-storage-config.md             |
| Golden templates DESIGN  | proxmox/golden_templates/DESIGN.md                |
| Golden VM Script         | proxmox/golden_templates/golden-vm-setup.sh       |
| Golden LXC Script        | proxmox/golden_templates/golden-lxc-setup.sh      |
| Backup layer DESIGN      | proxmox/backup/DESIGN.md                          |
| DR (host layer) DESIGN   | proxmox/disaster_recovery/DESIGN.md               |
| NAS Terraform (Dev)      | terraform/dev/proxmox/storage/nas/                |
| NAS Terraform (Prod)     | terraform/prod/proxmox/storage/nas/               |
| Storage Workflow         | .github/workflows/dev-proxmox-storage.yml         |
| K8s NFS CSI Driver       | kubernetes/dev/deployments/infrastructure/storage/nfs-csi-driver.yaml |
| K8s StorageClass         | kubernetes/dev/deployments/infrastructure/storage/storageclass.yaml |

---

## Environment Differences

| Setting            | Dev            | Prod           |
|--------------------|----------------|----------------|
| Hostname           | pve-dev        | pve-prod       |
| Admin user         | admin_dev      | admin_prod     |
| Terraform user     | tf_dev         | tf_prod        |
| WiFi interface     | wlp1s0         | wlp4s0         |
| Management IP      | 10.0.5.110     | 10.0.5.100     |
| Storage IP         | 10.0.40.110    | 10.0.40.100    |
| Service VLANs      | 60-65          | 50-55          |

---

## Continuous Improvements (Reference Only)

The following are optional enhancements, not required for initial setup:

- **Email Notifications**: Configure backup email alerts via proxmox/bootstrap_proxmox/mail-config.sh
- **UPS/Power Monitoring**: Laptop battery DR monitoring via proxmox/disaster_recovery/power/dr_ups_monitor.sh
- **Hardware Failure DR**: USB-Ethernet adapter replacement procedure in proxmox/disaster_recovery/hardware/usb-ethernet-adapter-replacement-guide.txt
- **Proxmox Config Backup**: Automated config backup script in proxmox/backup/

---

## Troubleshooting Reference

Key Proxmox troubleshooting cases, all under troubleshooting/proxmox/:

| TS case | File | Summary |
|---------|------|---------|
| TS-PVE-005 | 5-proxmox-backup-missed-not-retried.md | Missed backup not retried after host sleep — drove `repeat-missed=1` in vzdump config |
| TS-PVE-008 | 8-lvm-thin-pool-resize-overcommit.md | LVM thin pool ran out of space from over-provisioned VMs |
| TS-PVE-009 | 9-nfs-shutdown-hang-stor0-hotswap.md | Shutdown hangs when NFS mounts are active and USB-Ethernet stor0 is disconnected |
| TS-PVE-011 | 11-vmbr1-storage-network-for-k8s-workers.md | Adding vmbr1 (VLAN 40) second NIC to K8s worker VMs for direct NAS access |
| TS-PVE-012 | 12-vm-autostart-timeout-nfs-disk-not-ready.md | VMs fail autostart after reboot because NFS storage isn't ready yet |

Storage-related K8s cases (NFS PV issues) are under troubleshooting/kubernetes/.

---

## Deployment Order

Proxmox is step 1 — right after the physical network. For the full 0–15
sequence, see [README.md](README.md).

---
