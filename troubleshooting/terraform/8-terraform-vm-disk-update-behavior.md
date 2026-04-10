# TS-TF-008 | 2026-03-27 | RESOLVED

## 1. Context
- System: Terraform with bpg/proxmox provider
- Environment: Dev/Prod (pve-dev, pve-prod)
- Related components: K8s workers (1020, 1021, 1022), VM disk management, hotplug

## 2. Issue
- Symptom: Need to understand Terraform behavior when modifying VM disks - whether changes are in-place (safe) or replace/destroy (dangerous)
- Error: N/A (proactive documentation of disk update patterns)

**Change Required:** Remove 80GB data disk (scsi1) from K8s workers

## 3. Analysis

### Manual Testing Strategy

**Why Manual Test First?**

Before running `terraform plan`, performed manual testing via Proxmox GUI to:
1. Understand what Proxmox API will attempt to do
2. Identify potential blockers or requirements
3. Predict if operation needs VM stopped or can hotplug
4. Validate the configuration works before codifying

**Manual Test: Remove Disk (GUI)**
- VM Hardware → Select scsi1 → Detach → Remove
- Result: Success (hotplug worked on running VM)

**Insight:** Disk removal can be hot-removed without VM reboot.

### Terraform Plan Analysis

**Key Indicators in Plan Output:**

**Safe - In-place update:**
```
# proxmox_virtual_environment_vm.k8s_worker1 will be updated in-place
~ resource "proxmox_virtual_environment_vm" "k8s_worker1" {
```

**Dangerous - Replacement:**
```
# proxmox_virtual_environment_vm.k8s_worker1 must be replaced
-/+ resource "proxmox_virtual_environment_vm" "k8s_worker1" {
```

**Understanding Computed Attributes:**
```hcl
~ ipv4_addresses = [
    - ["127.0.0.1"],
    - ["10.0.64.10"],
  ] -> (known after apply)
```

The `-` (red) does NOT mean deletion. It shows current known values being replaced with values that will be computed after apply. This is normal for computed/read-only attributes.

### Disk Hotplug Capabilities

| Change Type | Hotplug? | Action Needed |
|-------------|----------|---------------|
| Add disk | Yes | None |
| Remove disk | Yes | None |
| Resize disk | Yes | Partition resize inside VM |
| Change datastore | No | Stop VM or recreate disk |

## 4. Root Cause
> Disk operations generally support hotplug in Proxmox, but Terraform state may not always sync correctly after removal. The provider updates state but may not fully clean up the actual disk from storage.

## 5. Solution
> Manual test in GUI first, run terraform plan to verify in-place update, then apply. Verify disk cleanup after removal.

### Best Practices for Disk Changes

**1. Manual Test First**
- Try the change manually via GUI/CLI
- Identify if hotplug works or VM stop needed
- Validate the configuration

**2. Always Run Plan First**
```bash
terraform plan
```
- Check for "must be replaced" warnings
- Review all changes carefully

**3. Verify After Disk Removal**

After any Terraform apply that removes disks:
```bash
# Check VM config - disk should be gone
qm config <vmid> | grep scsi

# List storage - check for orphaned disk files
pvesm list <storage-name> | grep <vmid>
```

**4. Handle Orphaned Disks**

If disk files remain after Terraform removal:
```bash
# Detach from VM (if still attached)
qm set <vmid> --delete scsi1

# Delete disk file from storage
pvesm free <storage>:<vmid>/<disk-file>
```

### Lifecycle Considerations

For existing VMs, protect against accidental recreation:
```hcl
lifecycle {
  ignore_changes = [clone]  # Don't recreate if template changes
}
```

Consider adding for production:
```hcl
lifecycle {
  prevent_destroy = true  # Block accidental destruction
}
```

## 6. Solution Risk
- Risk level: LOW for disk operations (hotplug supported)
- Potential impact: Orphaned disk files may remain on storage after removal - see TS-TF-011

## 7. Impact After Fix
- Observed: Disk removed successfully via Terraform
- VM continued running (no downtime)
- **Note:** Orphaned disk files discovered later - see TS-TF-011

## 8. Notes

### Summary: Disk Update Workflow

| Phase | Action | Purpose |
|-------|--------|---------|
| 1 | Manual test in GUI | Understand API behavior |
| 2 | terraform plan | Verify in-place vs replace |
| 3 | terraform apply | Execute changes |
| 4 | Verify cleanup | Check for orphaned disks |

### Related Cases

- **TS-TF-004:** Cloned VM disk tracking - how to properly declare disks for cloned VMs
- **TS-TF-011:** Orphaned disks after removal - consequence of this change, cleanup procedure

## 9. Workaround (if any)
> If Terraform disk removal causes issues: Remove disk manually via Proxmox GUI (`qm set --delete`), then remove disk block from Terraform and run `terraform apply` to sync state.

## Related Files
- `terraform/dev/proxmox/vms/k8s_workers/main.tf`
- `terraform/dev/proxmox/vms/k8s_workers/variables.tf`
