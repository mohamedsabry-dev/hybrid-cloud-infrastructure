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

## Root Cause

Set `os_disk.size = 15` in variables.tf, forgetting the golden image template (VMID 9001) has a 20GB base disk. Proxmox clones the full disk first, then tries to resize — and it can't shrink a disk, only grow it.

## Fix

Changed `os_disk.size` from 15 to 20 in `terraform/prod/proxmox/vms/testing/variables.tf`. Re-ran apply, passed clean.

## Rule

OS disk size in any VM module must be >= the golden image base size (currently 20GB). Terraform won't catch this at plan time — the error only surfaces during apply after the clone completes.
