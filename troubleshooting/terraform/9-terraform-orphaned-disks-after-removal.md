# Case 9: Terraform Orphaned Disks After Removal from Configuration

## Status: RESOLVED
## Date: 2026-03-27
## Environment: Proxmox pve-dev/pve-prod, NFS storage
## Affected: K8s workers (1020, 1021, 1022)

---

## Symptoms

After removing a disk block from Terraform configuration, Terraform updated its state file but did NOT:
1. Detach the disk from the VM
2. Delete the disk image from storage

This left orphaned disks attached to VMs and consuming storage space.

## Root Cause

### What Happened
1. Original Terraform config had two disks per worker (OS 25GB + data 80GB)
2. Data disk was removed from Terraform configuration
3. `terraform apply` ran successfully, updated state file
4. State file no longer contained disk-1 reference
5. However, the actual disk remained:
   - Still attached to VM as scsi1
   - Still existed on NAS storage as `vm-XXXX-disk-1.raw`

### Why Terraform Didn't Clean Up
1. **Provider Limitation**: The bpg/proxmox provider doesn't always handle disk removal properly. It updates state but may not issue the API call to detach.

2. **Data Safety**: Terraform providers are conservative about deleting storage to prevent accidental data loss.

3. **Hot-Remove Limitations**: Disks often can't be hot-removed from running VMs via API. Terraform may skip rather than fail.

4. **No Explicit Destroy**: Removing a block from config is different from `terraform destroy`. The provider may not interpret removal as "delete this resource."

## Detection

### Verify State File Doesn't Contain Disk
```bash
cd terraform/dev/proxmox/vms/k8s_workers
terraform state show proxmox_virtual_environment_vm.k8s_worker1 | grep -A5 disk
```

If only one disk block appears (scsi0/OS disk), the data disk was removed from state.

### Check VM Still Has Disk Attached
```bash
# On Proxmox host
qm config 1020 | grep -E "scsi|virtio|ide"
```

If `scsi1` appears with an 80GB disk, it's still attached despite being removed from Terraform.

### List Orphaned Disk Files on Storage
```bash
# List all disk images
pvesm list nas-dev-data | grep -E "1020|1021|1022"

# Compare with what should exist (only disk-0 for OS)
```

## Solution

### Step 1: Detach Disks from VMs
```bash
# On pve-dev
qm set 1020 --delete scsi1
qm set 1021 --delete scsi1
qm set 1022 --delete scsi1

# On pve-prod
qm set 1020 --delete scsi1
qm set 1021 --delete scsi1
qm set 1022 --delete scsi1
```

### Step 2: Delete Orphaned Disk Files
```bash
# On pve-dev
pvesm free nas-dev-data:1020/vm-1020-disk-1.raw
pvesm free nas-dev-data:1021/vm-1021-disk-1.raw
pvesm free nas-dev-data:1022/vm-1022-disk-1.raw

# On pve-prod
pvesm free nas-prod-data:1020/vm-1020-disk-1.raw
pvesm free nas-prod-data:1021/vm-1021-disk-1.raw
pvesm free nas-prod-data:1022/vm-1022-disk-1.raw
```

### Step 3: Verify Terraform State is Clean
```bash
terraform plan
# Should show "No changes"
```

## Additional Discovery: Old Storage Migration Orphans

During cleanup, we also found additional orphaned disks from a previous storage migration (NAS to local-lvm):

```
nas-prod-data:1020/vm-1020-disk-0.raw  80GB  (orphaned - VM boots from local-lvm)
nas-prod-data:1020/vm-1020-disk-2.raw  80GB  (orphaned)
nas-prod-data:1021/vm-1021-disk-0.raw  80GB  (orphaned)
nas-prod-data:1021/vm-1021-disk-2.raw  80GB  (orphaned)
nas-prod-data:1022/vm-1022-disk-0.raw  80GB  (orphaned)
nas-prod-data:1022/vm-1022-disk-2.raw  80GB  (orphaned)
```

### Verify Current Boot Disk Location
```bash
qm config 1020 | grep scsi0
# Output: scsi0: local-lvm:vm-1020-disk-0,size=25G
```

If VMs boot from `local-lvm`, NAS disk images are orphaned and safe to delete.

### Clean Up Storage Migration Orphans
```bash
# On pve-prod (~480GB freed)
pvesm free nas-prod-data:1020/vm-1020-disk-0.raw
pvesm free nas-prod-data:1020/vm-1020-disk-2.raw
pvesm free nas-prod-data:1021/vm-1021-disk-0.raw
pvesm free nas-prod-data:1021/vm-1021-disk-2.raw
pvesm free nas-prod-data:1022/vm-1022-disk-0.raw
pvesm free nas-prod-data:1022/vm-1022-disk-2.raw

# On pve-dev (~240GB freed)
pvesm free nas-dev-data:1020/vm-1020-disk-0.raw
pvesm free nas-dev-data:1021/vm-1021-disk-0.raw
pvesm free nas-dev-data:1022/vm-1022-disk-0.raw
```

## Prevention

### 1. Always Verify After Disk Removal
After any Terraform apply that removes disks:
```bash
# Check VM config
qm config <vmid> | grep scsi

# List storage
pvesm list <storage-name> | grep <vmid>
```

### 2. Stop VMs Before Disk Changes
```bash
# Stop VM first
qm stop 1020

# Apply Terraform
terraform apply

# Start VM
qm start 1020
```

### 3. Consider Manual Disk Management
For disk removal operations, consider:
1. Remove disk block from Terraform
2. Run `terraform apply`
3. Manually detach: `qm set <vmid> --delete <disk>`
4. Manually delete: `pvesm free <storage>:<vmid>/<disk-file>`

### 4. Regular Storage Audits
Periodically check for orphaned disks:
```bash
# List all disk images
pvesm list <storage> | grep images

# Compare against running VM configs
for vmid in $(qm list | awk 'NR>1 {print $1}'); do
  echo "=== VM $vmid ==="
  qm config $vmid | grep -E "scsi|virtio|ide" | grep -v net
done
```

## Lessons Learned

1. Terraform state removal != actual resource deletion for Proxmox disks
2. Always verify disk cleanup manually after Terraform changes
3. Storage migrations can leave orphaned disk images
4. Regular storage audits prevent wasted space
5. The bpg/proxmox provider is better at adding than removing disks
6. vzdump backups are self-contained and independent of disk images

## Related Files
- `terraform/dev/proxmox/vms/k8s_workers/main.tf`
- `terraform/prod/proxmox/vms/k8s_workers/main.tf`
