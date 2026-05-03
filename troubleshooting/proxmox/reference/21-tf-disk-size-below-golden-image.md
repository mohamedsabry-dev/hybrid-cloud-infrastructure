# TS-PVE-021: Terraform Disk Size Below Golden Image Base

**Date:** 2026-05-01
**Status:** Resolved
**Severity:** Low
**Environment:** PROD

## Symptom

Terraform apply failed after ~40s with:

```
Error: disk resize failure: requested size (15G) is lower than current size (20G)
```

Both test1 and test2 VMs hit this simultaneously.

## Evidence

```
Run terraform apply -auto-approve tfplan
╷
│ Warning: Deprecated Parameter
│
│ The parameter "dynamodb_table" is deprecated. Use parameter "use_lockfile"
│ instead.
╵
proxmox_virtual_environment_vm.test2: Creating...
proxmox_virtual_environment_vm.test1: Creating...
proxmox_virtual_environment_vm.test2: Still creating... [00m10s elapsed]
proxmox_virtual_environment_vm.test1: Still creating... [00m10s elapsed]
proxmox_virtual_environment_vm.test1: Still creating... [00m20s elapsed]
proxmox_virtual_environment_vm.test2: Still creating... [00m20s elapsed]
proxmox_virtual_environment_vm.test2: Still creating... [00m30s elapsed]
proxmox_virtual_environment_vm.test1: Still creating... [00m30s elapsed]
proxmox_virtual_environment_vm.test2: Still creating... [00m40s elapsed]
proxmox_virtual_environment_vm.test1: Still creating... [00m40s elapsed]
╷
│ Error: disk resize failure: requested size (15G) is lower than current size (20G)
│
│   with proxmox_virtual_environment_vm.test1,
│   on main.tf line 8, in resource "proxmox_virtual_environment_vm" "test1":
│    8: resource "proxmox_virtual_environment_vm" "test1" {
│
╵
╷
│ Error: disk resize failure: requested size (15G) is lower than current size (20G)
│
│   with proxmox_virtual_environment_vm.test2,
│   on main.tf line 133, in resource "proxmox_virtual_environment_vm" "test2":
│  133: resource "proxmox_virtual_environment_vm" "test2" {
│
╵
```

## Side Effect

The apply failed mid-create — both VMs were partially provisioned with only 1 disk (20GB OS disk from the clone) and incomplete configuration. Terraform state was left stale (resources half-created). Re-running `terraform apply` after fixing the disk size completed the configuration and reconciled the state. This is normal Terraform behavior — it picks up where it left off.

## Root Cause

Set `os_disk.size = 15` in variables.tf, forgetting the golden image template (VMID 9001) has a 20GB base disk. Proxmox clones the full disk first, then tries to resize — and it can't shrink a disk, only grow it.

## Fix

Changed `os_disk.size` from 15 to 20 in `terraform/prod/proxmox/vms/testing/variables.tf`. Re-ran apply, passed clean.

## Rule

OS disk size in any VM module must be >= the golden image base size (currently 20GB). Terraform won't catch this at plan time — the error only surfaces during apply after the clone completes.
