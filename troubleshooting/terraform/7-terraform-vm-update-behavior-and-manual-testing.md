# TS-59: Terraform VM Update Behavior and Manual Testing Strategy

## Problem Statement
When modifying existing VMs via Terraform, understanding whether changes will be:
- **In-place update** (safe, VM continues running)
- **Replace/Destroy** (dangerous, VM recreated, data loss)

This case documents the strategy of manual testing before Terraform apply and
understanding API behavior during partial failures.

## Environment
- Terraform Provider: bpg/proxmox
- Resources: proxmox_virtual_environment_vm
- VMs: k8s-worker1 (1020), k8s-worker2 (1021), k8s-worker3 (1022)

## Changes Required
1. Remove 80GB data disk (scsi1)
2. Add second network device (vmbr1, VLAN 40)
3. Add second ip_config in cloud-init (10.0.40.201/202/203)

## Manual Testing Strategy

### Why Manual Test First?
Before running `terraform plan`, performed manual testing via Proxmox GUI to:
1. Understand what Proxmox API will attempt to do
2. Identify potential blockers or requirements
3. Predict if operation needs VM stopped or can hotplug
4. Validate the configuration works before codifying

### Manual Test Steps Performed

**Step 1: Add Network Device (GUI)**
- VM Hardware -> Add -> Network Device
- Bridge: vmbr1, VLAN Tag: 40
- Result: Success (hotplug worked on running VM)

**Step 2: Update Cloud-Init IP Config (GUI)**
- VM Cloud-Init -> IP Config -> Add second IP
- IP: 10.0.40.201/24, No gateway
- Result: Config saved, but requires reboot to apply

**Step 3: Reboot VM**
- After reboot, second NIC (ens19) had IP configured
- Verified: `ip a` showed 10.0.40.201/24 on ens19

### Insights from Manual Testing
1. Network device can be hot-added (no reboot needed)
2. Cloud-init changes require VM reboot/restart
3. The order: add NIC first, then cloud-init, then reboot

## Terraform Plan Analysis

### Key Indicators in Plan Output

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

### Understanding Computed Attributes
```hcl
~ ipv4_addresses = [
    - ["127.0.0.1"],
    - ["10.0.64.10"],
  ] -> (known after apply)
```

The `-` (red) does NOT mean deletion. It shows current known values being
replaced with values that will be computed after apply. This is normal for
computed/read-only attributes.

### Our Plan Output
```
Plan: 0 to add, 3 to change, 0 to destroy.
```
- 0 destroy = Safe
- 3 change = In-place updates

## Partial Failure Scenario

### What Happened
First `terraform apply` with VMs running:
```
Error: error updating VM: received an HTTP 400 response - Reason:
Parameter verification failed. (ide2: hotplug problem - unable to change media type)
```

### Analysis
1. Terraform started modifying all 3 VMs in parallel
2. Network device was added successfully (hotplug OK)
3. Cloud-init (ide2) change failed (cannot hotplug)
4. Terraform errored out, state NOT updated

### Resulting State
- **Proxmox VMs**: Changes partially applied (NIC added, cloud-init updated)
- **Terraform State**: Still shows old configuration (no NIC, old cloud-init)
- **State Drift**: Terraform state doesn't match actual VM state

### Recovery Steps

**Step 1: Stop VMs**
```bash
qm stop 1020 && qm stop 1021 && qm stop 1022
```

**Step 2: Re-run Terraform Apply**
```bash
terraform apply
```

**Step 3: Observe Plan**
Plan now only shows:
```hcl
~ started = false -> true  # Just starting VMs
```
This confirms Terraform detected the changes were already made.

**Step 4: Apply to Sync State**
Apply completes, Terraform state now matches actual VMs.

## Best Practices Identified

### Before Terraform Changes to VMs

1. **Manual Test First**
   - Try the change manually via GUI/CLI
   - Identify if hotplug works or reboot needed
   - Validate the configuration

2. **Always Run Plan First**
   ```bash
   terraform plan
   ```
   - Check for "must be replaced" warnings
   - Review all changes carefully

3. **Check Hotplug Requirements**
   | Change Type | Hotplug? | Action Needed |
   |-------------|----------|---------------|
   | Add disk | Yes | None |
   | Remove disk | Yes | None |
   | Add NIC | Yes | None |
   | Remove NIC | Yes | None |
   | Cloud-init | No | Stop VM first |
   | CPU/Memory | Depends | Check settings |

4. **For Cloud-Init Changes**
   ```bash
   # Stop VMs first
   qm stop <vmid>
   # Then apply
   terraform apply
   # VMs will start with started=true
   ```

5. **Handle Partial Failures**
   - Don't panic - changes may already be applied
   - Check actual VM state in Proxmox
   - Re-run terraform plan to see remaining drift
   - Fix the blocker (e.g., stop VM)
   - Re-run apply to sync state

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

## Summary

| Phase | Action | Purpose |
|-------|--------|---------|
| 1 | Manual test in GUI | Understand API behavior |
| 2 | terraform plan | Verify in-place vs replace |
| 3 | Check hotplug needs | Stop VMs if cloud-init changes |
| 4 | terraform apply | Execute changes |
| 5 | Handle failures | Re-apply after fixing blockers |
| 6 | Verify | Check VMs have correct config |

## Related Files
- `terraform/dev/proxmox/vms/k8s_workers/main.tf`
- `terraform/dev/proxmox/vms/k8s_workers/variables.tf`

## Date
2026-03-27
