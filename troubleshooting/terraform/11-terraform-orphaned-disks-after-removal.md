# TS-TF-011 | 2026-03-27 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Terraform / Proxmox
Sub-techs: Terraform bpg/proxmox provider, disk removal, orphaned disks,
           NFS storage, pvesm, qm, storage audit
Environment: DEV & PROD | pve-dev, pve-prod | K8s workers (VM 1020, 1021, 1022)
             NAS storage: nas-dev-data, nas-prod-data
Re-opened: No

_____________________________________________________________________

[Issue Description]
After removing a disk block from Terraform configuration, terraform apply ran
successfully and updated the state file — but did NOT detach the disk from the
VM or delete the disk image from storage. Silent orphan creation.

  No Terraform error. Apply reported success.
  Disks remained attached to VMs as scsi1.
  Disk images remained on NAS storage consuming space.

Additional discovery during cleanup: orphaned disks from a previous storage
migration (NAS to local-lvm) were also found on NAS.

Related ticket: TS-TF-008 — disk update behaviour (the change that led to this)

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Checked state file vs actual VM config vs storage after apply.

  terraform state show proxmox_virtual_environment_vm.k8s_worker1 | grep -A5 disk
  → only scsi0 (OS disk) in state — data disk removed from state.

  qm config 1020 | grep -E "scsi|virtio|ide"
  → scsi1 still present with 80GB disk — still attached despite state removal.

  pvesm list nas-dev-data | grep -E "1020|1021|1022"
  → vm-1020-disk-1.raw still exists — disk file not deleted.

Why Terraform did not clean up:
  Provider limitation — bpg/proxmox does not reliably issue API calls to
  detach and delete disk files when a disk block is removed from config.
  This is partly by design (data safety) and partly because hot-removal via
  API is unreliable. Removing a block from config ≠ terraform destroy on
  that resource.

Additional orphaned disks discovered during cleanup — from a previous storage
migration where VMs were moved from NAS to local-lvm:

  On nas-prod-data:
    1020/vm-1020-disk-0.raw  80GB  (orphaned)
    1020/vm-1020-disk-2.raw  80GB  (orphaned)
    1021/vm-1021-disk-0.raw  80GB  (orphaned)
    1021/vm-1021-disk-2.raw  80GB  (orphaned)
    1022/vm-1022-disk-0.raw  80GB  (orphaned)
    1022/vm-1022-disk-2.raw  80GB  (orphaned)

  On nas-dev-data:
    1020/vm-1020-disk-0.raw  80GB  (orphaned)
    1021/vm-1021-disk-0.raw  80GB  (orphaned)
    1022/vm-1022-disk-0.raw  80GB  (orphaned)

  Verified VMs boot from local-lvm not NAS:
    qm config 1020 | grep scsi0
    → scsi0: local-lvm:vm-1020-disk-0,size=25G
  NAS images confirmed orphaned and safe to delete.


# Suspected Root Cause
bpg/proxmox provider updates Terraform state when a disk block is removed from
config but does not reliably issue the Proxmox API calls to detach and delete
the actual disk. Removing a disk block from Terraform config does not trigger
resource destruction for Proxmox disks — it only removes the state reference.


# More Checks Notes:
N/A — cause confirmed from VM config and storage listing.


# Suspected Solution
Manually detach orphaned disks from VMs (qm set --delete) and delete disk
image files from storage (pvesm free).


# Test
Detached and deleted all orphaned disks on dev and prod.
Ran terraform plan afterward.

Result: PASS — terraform plan shows No changes. ~720GB storage freed.

_____________________________________________________________________

[Final Root Cause]
Terraform state removal does not equal actual resource deletion for Proxmox
disks. The bpg/proxmox provider updates state when disk blocks are removed from
config but does not reliably issue API calls to detach disks or delete disk
image files. This is a provider limitation combined with conservative data-safety
behaviour. Disk removal requires explicit manual cleanup.

_____________________________________________________________________

[Final Solution]

Step 1 — Detach disks from VMs:

  On pve-dev:
    qm set 1020 --delete scsi1
    qm set 1021 --delete scsi1
    qm set 1022 --delete scsi1

  On pve-prod:
    qm set 1020 --delete scsi1
    qm set 1021 --delete scsi1
    qm set 1022 --delete scsi1

Step 2 — Delete orphaned disk files (Terraform removal, dev):
    pvesm free nas-dev-data:1020/vm-1020-disk-1.raw
    pvesm free nas-dev-data:1021/vm-1021-disk-1.raw
    pvesm free nas-dev-data:1022/vm-1022-disk-1.raw

  On pve-prod:
    pvesm free nas-prod-data:1020/vm-1020-disk-1.raw
    pvesm free nas-prod-data:1021/vm-1021-disk-1.raw
    pvesm free nas-prod-data:1022/vm-1022-disk-1.raw

Step 3 — Delete storage migration orphans (~720GB total):

  On pve-prod (~480GB freed):
    pvesm free nas-prod-data:1020/vm-1020-disk-0.raw
    pvesm free nas-prod-data:1020/vm-1020-disk-2.raw
    pvesm free nas-prod-data:1021/vm-1021-disk-0.raw
    pvesm free nas-prod-data:1021/vm-1021-disk-2.raw
    pvesm free nas-prod-data:1022/vm-1022-disk-0.raw
    pvesm free nas-prod-data:1022/vm-1022-disk-2.raw

  On pve-dev (~240GB freed):
    pvesm free nas-dev-data:1020/vm-1020-disk-0.raw
    pvesm free nas-dev-data:1021/vm-1021-disk-0.raw
    pvesm free nas-dev-data:1022/vm-1022-disk-0.raw

Step 4 — Verify Terraform state is clean:
  terraform plan  → No changes.

Verified: Yes

_____________________________________________________________________

[Risk Level] MEDIUM
Note: Data loss risk if wrong disks are deleted. Always verify VM boot disk
location before deleting. Confirm qm config shows VM boots from local-lvm
before freeing any NAS disk images.

_____________________________________________________________________

[References]
- TS-TF-008 — disk update behaviour (change that led to this discovery)

_____________________________________________________________________

[Draft Notes]

Always verify after any Terraform apply that removes disks:
  qm config <vmid> | grep scsi           check what is still attached
  pvesm list <storage> | grep <vmid>     check for orphaned files on storage

Workflow for reliable disk removal:
  1. Stop VM: qm stop <vmid>
  2. Remove disk block from Terraform config
  3. terraform apply
  4. Verify: qm config <vmid> | grep scsi
  5. If still attached: qm set <vmid> --delete <disk>
  6. If file still on storage: pvesm free <storage>:<vmid>/<disk-file>

Regular storage audit to detect orphaned disks:
  pvesm list <storage> | grep images
  for vmid in $(qm list | awk 'NR>1 {print $1}'); do
    echo "=== VM $vmid ==="
    qm config $vmid | grep -E "scsi|virtio|ide" | grep -v net
  done

Notes:
  1. Terraform state removal ≠ actual resource deletion for Proxmox disks
  2. Always manually verify disk cleanup after Terraform changes
  3. Storage migrations can leave orphaned disk images — audit periodically
  4. The bpg/proxmox provider is more reliable at adding than removing disks
  5. vzdump backups are self-contained and independent of disk images

Related files:
  terraform/dev/proxmox/vms/k8s_workers/main.tf
  terraform/prod/proxmox/vms/k8s_workers/main.tf