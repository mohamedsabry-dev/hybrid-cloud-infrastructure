# TS-TF-004 | 2026-03 | RESOLVED
_____________________________________________________________________

[Info]
Author:
Domain: Terraform / Proxmox
Sub-techs: Terraform bpg/proxmox provider, disk state tracking, LXC clone,
           hot-resize, UUID mounting, disk naming race condition, SCSI, LVM
Environment: DEV | pve-dev | FreeIPA VM (ID 1001) cloned from golden-image (ID 9000)
             Terraform 1.14.3, bpg/proxmox provider
Re-opened: No

_____________________________________________________________________

[Issue Description]
When adding a data disk to a cloned VM, Terraform exhibits unexpected behaviour
due to how it tracks disk state for cloned VMs. Provider does not populate disk
state from cloned VMs — disk array remains empty in tfstate despite scsi0
existing in Proxmox.

Terraform plan showed:
  ~ disk {
      ~ datastore_id = "local-lvm" -> "nas-dev-data"
      ~ interface    = "scsi0" -> "scsi1"
      ~ size         = 20 -> 25
  }
  - disk {
      - datastore_id = "nas-dev-data" -> null
      - interface    = "scsi1" -> null
  }

What Terraform tried to do:
  1. Transform scsi0 properties to match scsi1 configuration
  2. Delete what it thought was scsi1 (which did not exist yet)

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Checked state file after clone:

  terraform.tfstate after clone:
    "disk": []   ← empty despite scsi0 existing in Proxmox

  Provider does NOT track cloned disks in state. Terraform has no record of
  scsi0, so adding only scsi1 causes it to misinterpret the configuration.

Wrong approach that triggered the error:
  disk {
    datastore_id = "nas-dev-data"
    interface    = "scsi1"
    size         = 25
    file_format  = "raw"
  }

  Terraform sees: one disk in config (scsi1), no disk in state.
  Terraform plans: transform the unknown disk into scsi1 configuration.
  Result: chaos.


# Suspected Root Cause
bpg/proxmox provider does not populate disk state from cloned VMs. When a VM
is cloned, the disk array remains empty in Terraform state. Terraform is unaware
of scsi0 — adding only scsi1 causes it to misinterpret the entire disk configuration.


# More Checks Notes:
No additional checks needed — state file comparison confirmed the issue.
Solution direction was clear: explicitly declare both disks.


# Suspected Solution
Declare both disks explicitly — boot disk (scsi0) matching the golden image
template configuration, plus the new data disk (scsi1).


# Test
Added scsi0 declaration to Terraform config matching golden image template.
Re-ran plan.

Corrected plan:
  ~ disk { ~ discard = "ignore" -> "on" ~ ssd = false -> true }   (scsi0 adjusted)
  ~ disk { ~ size = 20 -> 25 }                                     (scsi1 managed)

Result: PASS — both disks properly tracked in state.

  Proxmox verification:
    Hard Disk (scsi0): local-lvm:vm-1001-disk-0,discard=on,size=20G,ssd=1
    Hard Disk (scsi1): nas-dev-data:1001/vm-1001-disk-0.raw,size=25G

  VM verification:
    lsblk
    sda  20G  (boot disk)
    sdb  25G  (data disk)

_____________________________________________________________________

[Final Root Cause]
bpg/proxmox provider does not populate disk state from cloned VMs. After clone,
the disk array in tfstate is empty. Terraform sees one disk in config (scsi1)
and nothing in state — it plans to transform or delete what it misidentifies as
an existing disk entry. Both disks must be explicitly declared for Terraform to
correctly track the state.

_____________________________________________________________________

[Final Solution]

Correct Terraform configuration — declare both disks:

  # Boot disk — must match golden image template exactly
  disk {
    datastore_id = var.datastore_id   # "local-lvm"
    interface    = "scsi0"
    size         = 20
    ssd          = true
    discard      = "on"
    file_format  = "raw"
  }

  # Data disk — new addition
  disk {
    datastore_id = "nas-dev-data"
    interface    = "scsi1"
    size         = 25
    ssd          = true
    discard      = "on"
    file_format  = "raw"
  }

tfstate after fix:
  disk[0]: datastore_id=local-lvm, interface=scsi0, size=20, ssd=true, discard=on
  disk[1]: datastore_id=nas-dev-data, interface=scsi1, size=25

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: No risk if scsi0 properties match golden image template. Mismatch would
cause Terraform to modify the boot disk properties.

_____________________________________________________________________

[References]
- TS-TF-011 — orphaned disks after removal
- archive/poc-v1-vsphere/troubleshooting/storage/3-disk-race-condition-disaster.md

_____________________________________________________________________

[Draft Notes]

_____________________________________________________________________
HOT RESIZE — expanding disk while VM is running
_____________________________________________________________________

Terraform/Proxmox supports hot-resizing disks without stopping the VM.
The Linux kernel automatically detects the capacity change via SCSI hotplug.

Test: resize scsi0 from 20GB to 25GB via GitHub Actions workflow (VM running).

Kernel log on resize:
  [ 547.891964] sd 0:0:0:0: Capacity data has changed
  [ 547.892203] sd 0:0:0:0: [sda] 52428800 512-byte logical blocks: (26.8 GB/25.0 GiB)
  [ 547.894498] sda: detected capacity change from 41943040 to 52428800

After resize: lsblk shows sda = 25G — no reboot needed.
Partition (sda3) still shows old size — filesystem expansion is manual:

  growpart /dev/sda 3     # grow partition to fill new space
  pvresize /dev/sda3      # resize LVM physical volume
  lvextend -l +100%FREE /dev/rl/root  # extend logical volume
  xfs_growfs /            # grow filesystem

Key findings:
  Hot resize works — Proxmox/Terraform can expand disks on a running VM.
  Kernel auto-detects — capacity change seen immediately via SCSI hotplug.
  No VM downtime — resize completes without stopping the VM.
  Manual filesystem expansion — still required inside the VM.


_____________________________________________________________________
DISK NAMING RACE CONDITION AFTER REBOOT
_____________________________________________________________________

After VM reboot, disk device names (sda, sdb) may swap:

  Before reboot:
    sda  20G  boot disk (scsi0) — has sda1/2/3 partitions, LVM
    sdb  25G  data disk (scsi1) — no partitions

  After reboot:
    sda  25G  data disk (no partitions)
    sdb  20G  boot disk — has all partitions, LVM

Why this happens:
  Linux does NOT guarantee sda = scsi0. Device names are assigned based on
  probe order, not SCSI interface ID. Whichever disk is detected first becomes
  sda. This is standard Linux behaviour, not a Terraform/Proxmox bug.

Why the system still boots correctly despite the swap:
  GRUB uses UUID to locate boot partition.
  LVM uses UUID for physical volume identification.
  /etc/fstab on Rocky Linux uses LVM device names (/dev/mapper/rl-root).
  The boot process does not rely on /dev/sda being the boot disk.

Never rely on device names (sda, sdb) for scripts, backups, or Ansible playbooks.

Always use persistent identifiers:
  By UUID:        /dev/disk/by-uuid/xxxx-xxxx
  By LVM name:    /dev/mapper/rl-root
  By SCSI path:   /dev/disk/by-path/pci-0000:00:1f.2-scsi-0:0:0:0  (scsi0)
                  /dev/disk/by-path/pci-0000:00:1f.2-scsi-0:0:1:0  (scsi1)
  By Proxmox ID:  /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0
                  /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1

Verify disk identity:
  ls -la /dev/disk/by-path/
  ls -la /dev/disk/by-id/ | grep scsi
  lsblk -o NAME,SIZE,HCTL,SERIAL


_____________________________________________________________________
FORMATTING AND MOUNTING DATA DISK WITH UUID
_____________________________________________________________________

Procedure after disk naming swap — identify and mount the data disk correctly.

Step 1 — Identify the data disk (scsi1):
  ls -la /dev/disk/by-id/ | grep scsi
  Example output:
    scsi-0QEMU_QEMU_HARDDISK_drive-scsi0 -> ../../sdb  (boot disk)
    scsi-0QEMU_QEMU_HARDDISK_drive-scsi1 -> ../../sda  (data disk)
  In this case sda is the data disk despite being named sda.

Step 2 — Create partition:
  fdisk /dev/sda  → n → p → 1 → Enter → Enter → w

Step 3 — Verify partition:
  lsblk
  Expected: sda1 25G part  (new partition on data disk)

Step 4 — Format as XFS:
  mkfs.xfs /dev/sda1

Step 5 — Create mount point:
  mkdir -p /data

Step 6 — Add to fstab using UUID (critical):
  echo "UUID=$(blkid -s UUID -o value /dev/sda1) /data xfs defaults 0 0" >> /etc/fstab

Step 7 — Mount:
  systemctl daemon-reload && mount /data

Step 8 — Verify:
  df -h /data
  tail -1 /etc/fstab
  Expected: UUID=316ecfbc-1fb3-46b3-8c0c-405b1213cf97 /data xfs defaults 0 0

Why UUID matters:
  Without UUID: /dev/sda1 in fstab → mount fails if disk swaps to sdb1 after reboot.
  With UUID:    UUID=316ecfbc-... in fstab → mounts correctly regardless of device name.

Quick one-liner (after fdisk):
  mkfs.xfs /dev/sda1 && \
  mkdir -p /data && \
  echo "UUID=$(blkid -s UUID -o value /dev/sda1) /data xfs defaults 0 0" >> /etc/fstab && \
  systemctl daemon-reload && mount /data && df -h /data


Key takeaways:
  1. Cloned VMs do not auto-track disks — provider leaves disk array empty in state
  2. Always declare boot disk (scsi0) explicitly when adding disks to cloned VMs
  3. scsi0 disk block must mirror golden image configuration exactly
  4. discard=on enables TRIM for SSD/thin-provisioned storage
  5. Hot resize supported — disks can be expanded while VM is running
  6. Disk device names are not stable across reboots — always use UUID or by-id paths

Workaround if needed:
  Add disk via Proxmox GUI, then import to Terraform state:
  terraform import proxmox_virtual_environment_vm.freeipa <node>/<vmid>

Related files:
  terraform/dev/proxmox/vms/golden-image/main.tf
  terraform/dev/proxmox/vms/freeipa/main.tf
  proxmox/golden_templates/golden-vm-setup.sh