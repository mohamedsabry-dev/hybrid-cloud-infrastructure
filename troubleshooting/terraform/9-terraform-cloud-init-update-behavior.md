# TS-TF-009 | 2026-03-27 | RESOLVED

## 1. Context
- System: Terraform with bpg/proxmox provider
- Environment: Dev/Prod (pve-dev, pve-prod)
- Related components: K8s workers (1020, 1021, 1022), cloud-init, network devices

## 2. Issue
- Symptom: Need to understand Terraform behavior when modifying cloud-init configuration - hotplug limitations and reboot requirements
- Error:
```
Error: error updating VM: received an HTTP 400 response - Reason:
Parameter verification failed. (ide2: hotplug problem - unable to change media type)
```

**Changes Required:**
1. Add second network device (vmbr1, VLAN 40)
2. Add second ip_config in cloud-init (10.0.40.201/202/203)

## 3. Analysis

### Manual Testing Strategy

**Why Manual Test First?**

Before running `terraform plan`, performed manual testing via Proxmox GUI to:
1. Understand what Proxmox API will attempt to do
2. Identify potential blockers or requirements
3. Predict if operation needs VM stopped or can hotplug
4. Validate the configuration works before codifying

**Manual Test Steps Performed:**

**Step 1: Add Network Device (GUI)**
- VM Hardware → Add → Network Device
- Bridge: vmbr1, VLAN Tag: 40
- Result: Success (hotplug worked on running VM)

**Step 2: Update Cloud-Init IP Config (GUI)**
- VM Cloud-Init → IP Config → Add second IP
- IP: 10.0.40.201/24, No gateway
- Result: Config saved, but requires reboot to apply

**Step 3: Reboot VM**
- After reboot, second NIC (ens19) had IP configured
- Verified: `ip a` showed 10.0.40.201/24 on ens19

**Insights from Manual Testing:**
1. Network device can be hot-added (no reboot needed)
2. Cloud-init changes require VM reboot/restart
3. The order: add NIC first, then cloud-init, then reboot

### Cloud-Init Hotplug Limitations

| Change Type | Hotplug? | Action Needed |
|-------------|----------|---------------|
| Add NIC | Yes | None |
| Remove NIC | Yes | None |
| Cloud-init ip_config | **No** | Stop VM first |
| Cloud-init user_account | **No** | Stop VM first |
| Cloud-init dns | **No** | Stop VM first |

**Key Finding:** Cloud-init configuration (ide2) cannot be hot-changed on running VMs.

### Partial Failure Scenario

**What Happened:**

First `terraform apply` with VMs running:
```
Error: error updating VM: received an HTTP 400 response - Reason:
Parameter verification failed. (ide2: hotplug problem - unable to change media type)
```

**Analysis:**
1. Terraform started modifying all 3 VMs in parallel
2. Network device was added successfully (hotplug OK)
3. Cloud-init (ide2) change failed (cannot hotplug)
4. Terraform errored out, state NOT updated

**Resulting State:**
- **Proxmox VMs**: Changes partially applied (NIC added, cloud-init updated in config)
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

## 4. Root Cause
> Cloud-init configuration (ide2) cannot be hot-changed on running VMs. Terraform attempted to modify all 3 VMs in parallel; network device succeeded (hotplug OK) but cloud-init failed, leaving VMs in partial state with Terraform state not updated.

## 5. Solution
> Stop VMs before applying cloud-init changes. Handle partial failures by re-running apply after stopping VMs.

### Best Practices for Cloud-Init Changes

**1. Always Stop VMs First**
```bash
# Stop VMs before cloud-init changes
qm stop <vmid>

# Then apply Terraform
terraform apply

# VMs will start automatically if started=true in config
```

**2. For Multiple VMs**
```bash
# Stop all affected VMs
qm stop 1020 && qm stop 1021 && qm stop 1022

# Apply changes
terraform apply
```

**3. Handle Partial Failures**
- Don't panic - changes may already be applied
- Check actual VM state in Proxmox GUI
- Re-run terraform plan to see remaining drift
- Stop VMs if not already stopped
- Re-run apply to sync state

## 6. Solution Risk
- Risk level: MEDIUM
- Potential impact: VM downtime required for cloud-init changes
- **Hidden risk discovered after this change:** Cloud-init re-ran and regenerated SSH host keys, breaking SSH authentication. See TS-TF-010 for full incident and recovery.

## 7. Impact After Fix
- Observed: All 3 VMs updated with second NIC and IP
- Terraform state matches actual VM configuration
- VMs running with correct network configuration

## 8. Notes

### Summary: Cloud-Init Update Workflow

| Phase | Action | Purpose |
|-------|--------|---------|
| 1 | Manual test in GUI | Understand API behavior |
| 2 | terraform plan | Verify changes |
| 3 | Stop VMs | Required for cloud-init changes |
| 4 | terraform apply | Execute changes |
| 5 | Handle failures | Re-apply after stopping VMs |
| 6 | Verify | Check VMs have correct config |

### Lifecycle Considerations

For existing VMs, protect against accidental recreation:
```hcl
lifecycle {
  ignore_changes = [clone]  # Don't recreate if template changes
}
```

### Related Cases

- **TS-TF-008:** VM disk update behavior - companion case for disk changes
- **TS-TF-010:** Cloud-init SSH host key regeneration - consequence of this change

## 9. Workaround (if any)
> If cloud-init changes must be applied without Terraform: Make changes directly in Proxmox GUI, stop/start VM, then run `terraform refresh` to sync state.

## Related Files
- `terraform/dev/proxmox/vms/k8s_workers/main.tf`
- `terraform/dev/proxmox/vms/k8s_workers/variables.tf`
