# TS-TF-001 | 2026-02 | RESOLVED

## 1. Context
- System: Terraform with bpg/proxmox provider
- Environment: Proxmox VE (pve-dev)
- Related components: Rocky Linux 10.1 golden image, QCOW2 cloud images, cloud-init

## 2. Issue
- Symptom: Multiple errors when setting up golden image VM using QCOW2 cloud images via Terraform
- Error: Various errors including storage issues, permission issues, and parsing failures

**Final Resolution:** Reverted to standard ISO installation approach due to multiple provider limitations with QCOW2 cloud images.

## 3. Analysis

**Issue 1: Snippets content type not enabled**
```
Error: error creating file: received an HTTP 500 response - Reason: Parameter verification failed.
storage 'local' does not support content-type 'snippets'
```
Fix:
```bash
mkdir -p /var/lib/vz/snippets
/usr/sbin/pvesm set local --content backup,iso,vztmpl,snippets
```

**Issue 2: pvesm command not found**
```
-bash: pvesm: command not found
```
Fix: Use full path `/usr/sbin/pvesm` or run as root.

**Issue 3: Permission denied writing snippets**
```
Error: error creating file: failed to upload file - permission denied
```
Fix:
```bash
chown root:admin_dev /var/lib/vz/snippets
chmod 775 /var/lib/vz/snippets
```

**Issue 4: ipcc_send_rec failed**
```
Error: creating custom disk: ipcc_send_rec[1] failed: Unknown error -1
```
Fix:
```bash
systemctl restart pvedaemon pveproxy pvestatd
```

**Issue 5-7: Unable to parse directory volume name**
```
Error: creating custom disk: unable to parse directory volume name 'iso/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2'
```
Finding: Provider cannot parse directory-based storage volume names (local, NFS, CIFS) for QCOW2 imports.

**Issue 8: Download file wrong extension**
```
Error: error download file by URL: received an HTTP 400 response - wrong file extension
```
Finding: Proxmox rejects `.qcow2` for `iso` content type.

## 4. Root Cause
> The bpg/proxmox Terraform provider (v0.93.1) has fundamental limitations with QCOW2 cloud images:
> 1. Cannot parse directory-based storage volume names for disk imports
> 2. Download_file resource validates extensions against content types
> 3. Provider expects specific volume name formats, not arbitrary filenames

## 5. Solution
> Reverted to standard ISO installation approach.

**Why ISO approach works better:**
- Standard `.iso` files fully supported by Proxmox
- Attaches ISO as CD-ROM for installation
- Manual or kickstart-automated installation
- More reliable with current provider version

**Related files:**
- Bootstrap: `proxmox/bootstrap_proxmox/bootstrap.sh`
- Terraform: `terraform/dev/proxmox/vms/golden-image/`
- Cleanup: `proxmox/golden_templates/golden-vm-setup.sh`

## 6. Solution Risk
- Risk level: LOW
- Potential impact: ISO installation requires more manual steps than cloud images

## 7. Impact After Fix
- Observed: Golden image created successfully via ISO
- VMs can be cloned from template
- No provider limitations with ISO approach

## 8. Notes

**Lessons learned:**
1. QCOW2 cloud images are designed for cloud platforms (OpenStack, AWS), limited Proxmox Terraform support
2. Directory-based storage in Proxmox has different volume naming conventions
3. Standard ISO installation is more reliable for Proxmox golden images
4. Test provider limitations early when adopting new patterns

## 9. Workaround (if any)
> Manual `qm importdisk` as root can import QCOW2 images, but not manageable via Terraform state.
