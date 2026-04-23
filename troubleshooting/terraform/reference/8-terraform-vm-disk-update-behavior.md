# TS-TF-008 | 2026-03-27 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Terraform / Proxmox
Sub-techs: Terraform bpg/proxmox provider, VM disk management, hotplug,
           disk removal, orphaned disks, Proxmox qm
Environment: DEV & PROD | pve-dev, pve-prod | K8s workers (VM 1020, 1021, 1022)
Re-opened: No

_____________________________________________________________________

[Issue Description]
Proactive documentation — not a live failure.
Need to understand Terraform behaviour when modifying VM disks: whether changes
are in-place (safe) or replace/destroy (dangerous) before executing.

Change required: remove 80GB data disk (scsi1) from K8s worker VMs.

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Manual test performed via Proxmox GUI before running terraform plan — to
understand what the API will do, identify blockers, and predict hotplug behaviour.

Manual test — remove disk via GUI:
  VM Hardware → select scsi1 → Detach → Remove
  Result: success. Hotplug worked on running VM. No reboot needed.

Disk hotplug capabilities:
  Add disk         → hotplug supported, no action needed
  Remove disk      → hotplug supported, no action needed
  Resize disk      → hotplug supported, partition resize needed inside VM
  Change datastore → no hotplug, VM must be stopped or disk recreated

Ran terraform plan to verify update type:

  Safe — in-place update (what we want):
    # proxmox_virtual_environment_vm.k8s_worker1 will be updated in-place
    ~ resource "proxmox_virtual_environment_vm" "k8s_worker1" {

  Dangerous — replacement (what to avoid):
    # proxmox_virtual_environment_vm.k8s_worker1 must be replaced
    -/+ resource "proxmox_virtual_environment_vm" "k8s_worker1" {

Confirmed in-place update — safe to proceed.

Understanding computed attributes in plan output:
  ~ ipv4_addresses = [
      - ["127.0.0.1"],
      - ["10.0.64.10"],
    ] -> (known after apply)

  The - (red) does NOT mean deletion. It shows current known values being
  replaced by values computed after apply. Normal for read-only attributes.


# Suspected Root Cause
N/A — proactive documentation. No failure to diagnose.


# More Checks Notes:
After disk removal, provider updates state but may not fully clean up actual
disk files from storage. Orphaned disk files can remain — see TS-TF-011.


# Suspected Solution
Manual test first → terraform plan to verify in-place → terraform apply →
verify disk cleanup.


# Test
Removed scsi1 disk block from Terraform config, ran plan (confirmed in-place),
applied.

Command:
  qm config <vmid> | grep scsi
  pvesm list <storage-name> | grep <vmid>

Result: PASS — disk removed, VM continued running, no downtime.
Note: orphaned disk files discovered afterward — see TS-TF-011.

_____________________________________________________________________

[Final Root Cause]
N/A — proactive investigation. No incident.

_____________________________________________________________________

[Final Solution]
Standard workflow for VM disk changes:

  Phase 1 — Manual test in GUI:
    Try the change manually via Proxmox GUI or qm CLI.
    Confirm hotplug works or identify if VM stop is needed.

  Phase 2 — terraform plan:
    Verify change is in-place (~) not replacement (-/+).
    Review all computed attribute changes — red (-) does not always mean deletion.

  Phase 3 — terraform apply:
    Execute changes.

  Phase 4 — verify cleanup:
    qm config <vmid> | grep scsi         disk should be absent
    pvesm list <storage-name> | grep <vmid>   check for orphaned files

  If orphaned disk files remain:
    qm set <vmid> --delete scsi1                 detach if still attached
    pvesm free <storage>:<vmid>/<disk-file>      delete the file

Lifecycle blocks for production VMs:
  lifecycle {
    ignore_changes  = [clone]       do not recreate if template changes
    prevent_destroy = true          block accidental destruction
  }

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: Disk removal supports hotplug — no VM downtime. Orphaned disk files
may remain on storage after Terraform removal and require manual cleanup.

_____________________________________________________________________

[References]
- TS-TF-004 — cloned VM disk tracking
- TS-TF-011 — orphaned disks after removal (consequence of this change)

_____________________________________________________________________

[Draft Notes]

Disk change summary:
  Add disk         hotplug yes   no downtime
  Remove disk      hotplug yes   no downtime, check for orphaned files
  Resize disk      hotplug yes   no downtime, manual partition resize inside VM
  Change datastore hotplug no    VM stop required or disk recreation

If Terraform disk removal causes issues:
  Remove disk manually via Proxmox GUI (qm set <vmid> --delete scsi1).
  Remove disk block from Terraform config.
  Run terraform apply to sync state.

Related files:
  terraform/dev/proxmox/vms/k8s_workers/main.tf
  terraform/dev/proxmox/vms/k8s_workers/variables.tf