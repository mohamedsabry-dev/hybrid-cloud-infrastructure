# Terraform Troubleshooting Cases

Documentation of issues encountered with Terraform, primarily using the bpg/proxmox provider, AWS provider, and related infrastructure automation.

---

## Cases

| # | Ticket ID | Date | Issue | Root Cause |
|---|-----------|------|-------|------------|
| 1 | [TS-TF-001](1-proxmox-golden-image-terraform.md) | 2026-02 | Golden image creation workflow | Terraform + Packer + Proxmox integration |
| 2 | [TS-TF-002](2-aws-secrets-deletion-incident.md) | 2026-02-14 | AWS secrets scheduled for deletion | No approval gate, workflow canceled mid-apply |
| 3 | [TS-TF-003](3-terraform-proxmox-lxc-clone-ssh-keys.md) | 2026-02-23 | LXC clones have wrong SSH keys | Clone copies source keys, vzdump template solution |
| 4 | [TS-TF-004](4-terraform-proxmox-cloned-vm-disk-tracking.md) | 2026-03 | Cloned VM disk not tracked by Terraform | Cloned disks need explicit declaration |
| 5 | [TS-TF-005](5-terraform-proxmox-lxc-mount-point-bug.md) | 2026-03 | LXC mount point configuration issue | Provider mount point handling bug |
| 6 | [TS-TF-006](6-route-table-inline-vs-resource.md) | 2026-03-14 | Route table removes routes from other modules | Inline routes own all routes in table |
| 7 | [TS-TF-007](7-terraform-security-group-rename-stuck.md) | 2026-03-21 | Security group rename causes stuck resources | AWS name changes cause replacement |
| 8 | [TS-TF-008](reference/8-terraform-vm-disk-update-behavior.md) | 2026-03-27 | VM disk update behavior and hotplug | Disk operations support hotplug, verify cleanup |
| 9 | [TS-TF-009](9-terraform-cloud-init-update-behavior.md) | 2026-03-27 | Cloud-init changes require VM stop | Cloud-init (ide2) cannot hotplug |
| 10 | [TS-TF-010](10-cloud-init-ssh-host-key-regeneration.md) | 2026-03-27 | SSH host keys regenerated after cloud-init change | Cloud-init re-runs regenerate SSH keys by default |
| 11 | [TS-TF-011](11-terraform-orphaned-disks-after-removal.md) | 2026-03-27 | Orphaned disks after removal from config | Provider updates state but doesn't delete disk files |

---

## Quick Reference

### Proxmox VM/LXC Management
- **Case 1:** Golden image → Terraform + Packer workflow for template creation
- **Case 3:** LXC wrong SSH keys → Use vzdump template instead of clone
- **Case 4:** Cloned disk not tracked → Explicitly declare disk blocks for cloned VMs
- **Case 5:** LXC mount point → Provider mount point handling workarounds
- **Case 8:** Disk changes → Hotplug supported, verify cleanup after removal
- **Case 9:** Cloud-init changes → Stop VM first, cannot hotplug ide2
- **Case 10:** SSH keys changed → Restore from backup or update FreeIPA
- **Case 11:** Orphaned disks → Manual cleanup with `qm set --delete` + `pvesm free`

### AWS Resources
- **Case 2:** Secrets deleted → Implement approval gates, enable S3 versioning
- **Case 6:** Route conflicts → Use separate `aws_route` resources, not inline routes
- **Case 7:** Security group rename → AWS name changes cause resource replacement

---

## Case Chains

### Cloud-Init Update Chain (Cases 8 → 9 → 10 → 11)
Related cases covering VM update workflow and consequences:
1. **Case 8:** Disk update behavior - hotplug patterns
2. **Case 9:** Cloud-init update behavior - requires VM stop
3. **Case 10:** SSH key regeneration - consequence of cloud-init re-run
4. **Case 11:** Orphaned disks - cleanup after disk removal

### Inline vs Separate Resources (Cases 6 + 7)
AWS pattern: Avoid inline blocks when resources are managed across modules:
- **Case 6:** Route table routes → Use `aws_route`
- **Case 7:** Security group rules → Name changes cause replacement

---

## Related Cases in Other Folders

| Case | Folder | Topic |
|------|--------|-------|
| TS-GH-002 | github/ | Workflow lock flag pattern (related to Case 2) |
| TS-GH-004 | github/ | Git history secrets cleanup |

---

## Environment

- **Providers:** bpg/proxmox, hashicorp/aws
- **Backend:** S3 + DynamoDB (AWS), local (Proxmox dev)
- **Proxmox:** pve-dev, pve-prod clusters
- **Automation:** GitHub Actions with self-hosted runners

---

