# TS-TF-009 | 2026-03-27 | RESOLVED
_____________________________________________________________________

[Info]
Author:
Domain: Terraform / Proxmox
Sub-techs: Terraform bpg/proxmox provider, cloud-init, hotplug limitations,
           network devices, partial failure recovery, Proxmox qm
Environment: DEV & PROD | pve-dev, pve-prod | K8s workers (VM 1020, 1021, 1022)
Re-opened: No

_____________________________________________________________________

[Issue Description]
Terraform failed when modifying cloud-init configuration on running VMs.

  Error: error updating VM: received an HTTP 400 response
  Parameter verification failed. (ide2: hotplug problem - unable to change media type)

Changes required:
  1. Add second network device (vmbr1, VLAN 40)
  2. Add second ip_config in cloud-init (10.0.40.201/202/203 on each worker)

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Manual test performed via Proxmox GUI before running terraform plan.

Step 1 — Add network device (GUI):
  VM Hardware → Add → Network Device, bridge vmbr1, VLAN tag 40.
  Result: success. Hotplug worked on running VM.

Step 2 — Update cloud-init IP config (GUI):
  VM Cloud-Init → IP Config → add second IP (10.0.40.201/24, no gateway).
  Result: config saved but required reboot to apply.

Step 3 — Reboot VM:
  After reboot, ens19 had 10.0.40.201/24 configured. Verified with ip a.

Cloud-init hotplug capabilities:
  Add NIC               hotplug yes   no action needed
  Remove NIC            hotplug yes   no action needed
  cloud-init ip_config  hotplug NO    VM must be stopped first
  cloud-init user_account hotplug NO  VM must be stopped first
  cloud-init dns        hotplug NO    VM must be stopped first

Key finding: cloud-init configuration (ide2) cannot be changed on a running VM.

What happened on first terraform apply (VMs running):
  Terraform started modifying all 3 VMs in parallel.
  Network device added successfully (hotplug OK).
  Cloud-init (ide2) change failed (cannot hotplug).
  Terraform errored, state NOT updated.

Resulting state after partial failure:
  Proxmox VMs:      changes partially applied (NIC added, cloud-init updated in config)
  Terraform state:  still shows old configuration (no NIC, old cloud-init)
  State drift:      Terraform state does not match actual VM state


# Suspected Root Cause
Cloud-init configuration (ide2) cannot be hot-changed on running VMs.
Terraform applied changes in parallel — network device succeeded but cloud-init
failed, leaving VMs in partial state with Terraform state not updated.


# More Checks Notes:
Hidden risk discovered after this change: cloud-init re-ran and regenerated
SSH host keys on restart, breaking SSH authentication.
See TS-TF-010 for full incident and recovery.


# Suspected Solution
Stop VMs before applying cloud-init changes. Handle partial failure by
stopping VMs and re-running apply — changes may already be in Proxmox config.


# Test
Stopped all three K8s workers, re-ran terraform apply.

Plan after stopping VMs:
  ~ started = false -> true   (just starting VMs — changes already detected as applied)

Apply completed. Terraform state now matches actual VMs.

Result: PASS — all 3 workers updated with second NIC and cloud-init IP config.
VMs running with correct network configuration.

_____________________________________________________________________

[Final Root Cause]
Proxmox API does not allow cloud-init (ide2) changes on a running VM. Terraform
attempted parallel modification of all 3 workers — network device change succeeded
(hotplug supported) but cloud-init change failed, leaving VMs partially updated
and Terraform state out of sync.

_____________________________________________________________________

[Final Solution]
Stop VMs before any cloud-init change, then apply:

  qm stop 1020 && qm stop 1021 && qm stop 1022
  terraform apply
  (VMs start automatically if started=true in config)

Handling partial failure (if apply errored mid-run):
  1. Do not panic — changes may already be in Proxmox config.
  2. Check actual VM state in Proxmox GUI.
  3. Run terraform plan to see remaining drift.
  4. Stop VMs if not already stopped.
  5. Re-run terraform apply — Terraform detects already-applied changes
     and only syncs state (plan shows started = false -> true).

If cloud-init changes must be applied without Terraform:
  Make changes directly in Proxmox GUI.
  Stop and start VM to apply cloud-init.
  Run terraform refresh to sync state.

Verified: Yes

_____________________________________________________________________

[Risk Level] MEDIUM
Note: VM downtime required for cloud-init changes.
Additional hidden risk: cloud-init re-ran on restart and regenerated SSH host
keys — see TS-TF-010 for full incident and recovery procedure.

_____________________________________________________________________

[References]
- TS-TF-008 — VM disk update behaviour (companion case)
- TS-TF-010 — cloud-init SSH host key regeneration (consequence of this change)

_____________________________________________________________________

[Draft Notes]

Cloud-init update workflow:
  Phase 1  Manual test in GUI      understand API behaviour, confirm hotplug limits
  Phase 2  terraform plan          verify changes before executing
  Phase 3  Stop VMs                required for cloud-init changes
  Phase 4  terraform apply         execute changes
  Phase 5  Handle partial failures re-apply after stopping VMs if errored
  Phase 6  Verify                  check VMs have correct config, check SSH keys

Lifecycle block for production VMs:
  lifecycle {
    ignore_changes = [clone]       do not recreate if template changes
  }

Related files:
  terraform/dev/proxmox/vms/k8s_workers/main.tf
  terraform/dev/proxmox/vms/k8s_workers/variables.tf