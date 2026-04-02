# Case 1: Proxmox Golden Image Terraform Setup — QCOW2 Issues

## Status: RESOLVED (Workaround)
## Date: 2026-02
## Environment: Proxmox VE with bpg/proxmox Terraform provider

---

## Symptoms

Multiple issues encountered while setting up Rocky Linux 10.1 golden image VM using Terraform with the bpg/proxmox provider, specifically attempting to use QCOW2 cloud images.

**Final Resolution:** Reverted to standard ISO installation approach due to multiple provider limitations with QCOW2 cloud images.

---

## Issue 1: Snippets Content Type Not Enabled

### Error
```
Error: error creating file: received an HTTP 500 response - Reason: Parameter verification failed.
storage 'local' does not support content-type 'snippets'
```

### Cause
Proxmox local storage doesn't have snippets content type enabled by default. Cloud-init user_data files need to be stored as snippets.

### Solution
Run on Proxmox host as root:
```bash
mkdir -p /var/lib/vz/snippets
/usr/sbin/pvesm set local --content backup,iso,vztmpl,snippets
```

---

## Issue 2: pvesm Command Not Found

### Error
```
-bash: pvesm: command not found
```

### Cause
Proxmox management commands are not in the PATH for non-root users.

### Solution
Use full path:
```bash
/usr/sbin/pvesm set local --content backup,iso,vztmpl,snippets
```

Or run as root directly.

---

## Issue 3: Permission Denied Writing Snippets

### Error
```
Error: error creating file: failed to upload file - failed to open remote file - open /var/lib/vz/snippets/...: permission denied
```

### Cause
The admin user doesn't have write permissions to the snippets directory.

### Solution
Set proper permissions on Proxmox host:
```bash
chown root:admin_dev /var/lib/vz/snippets
chmod 775 /var/lib/vz/snippets
```

For production, use `admin_prod` group instead.

---

## Issue 4: ipcc_send_rec Failed Error

### Error
```
Error: creating custom disk: ipcc_send_rec[1] failed: Unknown error -1
Unable to load access control list: Unknown error -1
```

### Cause
Proxmox internal process communication (IPC) issue. Can occur due to:
- Stale Proxmox daemon state
- Permission issues with API token
- Internal service communication problems

### Solution
Restart Proxmox services:
```bash
systemctl restart pvedaemon pveproxy pvestatd
```

---

## Issue 5: Unable to Parse Directory Volume Name (NAS Storage)

### Error
```
Error: creating custom disk: unable to parse directory volume name 'iso/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2'
```

### Cause
The bpg/proxmox Terraform provider has specific parsing logic for disk imports:
- Directory-based storage (local, NFS/NAS) uses different volume naming than LVM storage
- Files in `iso/` content area are not recognized as importable disk images
- The provider distinguishes between `iso` (CD/DVD images) and `images` (VM disk images) content types

### Attempted Workaround
Changed variable to reference NAS images folder:
```hcl
variable "cloud_image_file_id" {
  default = "nas-iso:iso/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2"
}
```

### Result
Same parsing error - provider cannot parse directory-based volume names for QCOW2 imports.

---

## Issue 6: Unable to Parse Directory Volume Name (NAS Images Folder)

### Error
```
Error: creating custom disk: unable to parse directory volume name 'images/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2'
```

### Attempted Workaround
1. Enabled images content type on NAS storage:
```bash
pvesm set nas-iso --content iso,images
mkdir -p /mnt/pve/nas-iso/images
mv /mnt/pve/nas-iso/template/iso/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2 /mnt/pve/nas-iso/images/
```

2. Updated Terraform variable:
```hcl
variable "cloud_image_file_id" {
  default = "nas-iso:images/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2"
}
```

### Result
Still failed - provider has fundamental issues parsing directory storage volume names regardless of content type.

---

## Issue 7: Unable to Parse Directory Volume Name (Local Storage)

### Error
```
Error: creating custom disk: unable to parse directory volume name 'iso/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2'
```

### Attempted Workaround
Copied QCOW2 to local storage:
```bash
cp /mnt/pve/nas-iso/template/iso/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2 /var/lib/vz/template/iso/
```

Updated variable:
```hcl
variable "cloud_image_file_id" {
  default = "local:iso/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2"
}
```

### Result
Same error - `local` storage is also directory-based, so the provider has the same parsing issues.

---

## Issue 8: Download File Wrong Extension Error

### Error
```
Error: Error downloading file from url
Could not download file 'Rocky-10-GenericCloud-Base.latest.x86_64.qcow2',
unexpected error: error download file by URL: received an HTTP 400 response
- Reason: Parameter verification failed. (filename: wrong file extension)
```

### Attempted Workaround
Used `proxmox_virtual_environment_download_file` resource to download directly from Rocky Linux:
```hcl
resource "proxmox_virtual_environment_download_file" "rocky_cloud_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = var.node_name
  url          = "https://download.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2"
  file_name    = "Rocky-10-GenericCloud-Base.latest.x86_64.qcow2"
}
```

### Result
Proxmox rejects the download because `.qcow2` extension doesn't match `iso` content type. The provider validates file extensions against content types.

---

## Issue 9: QCOW2 Not Visible in Proxmox Web UI

### Observation
QCOW2 file copied to `/var/lib/vz/template/iso/` doesn't appear in Proxmox web UI under "ISO Images".

### Cause
Proxmox web UI filters by file extension - only `.iso` files are shown in the ISO Images view.

### Note
This is cosmetic only but indicates Proxmox's preference for standard file types.

---

## Issue 10: qm Command Not Found for Non-Root User

### Error
```
-bash: qm: command not found
```

### Cause
The `qm` command is a Proxmox management tool that requires root privileges and is located in `/usr/sbin/`.

### Solution
Use sudo or login as root:
```bash
sudo qm importdisk 9000 /path/to/image.qcow2 local-lvm --format qcow2
```

---

## Root Cause Analysis

The bpg/proxmox Terraform provider (v0.93.1) has limitations with QCOW2 cloud images:

1. **Directory storage parsing**: The provider cannot properly parse volume names for directory-based storage (local, NFS, CIFS) when importing disk images.

2. **Content type validation**: The download_file resource validates file extensions against content types, rejecting `.qcow2` files for `iso` content type.

3. **Volume name format expectations**: The provider expects disk images in specific formats like `storage:images/vm-XXX-disk-0.qcow2` or `storage:base/XXX-disk-0`, not arbitrary filenames.

4. **LVM vs Directory storage**: LVM-based storage (like `local-lvm`) works differently and is the target for disk imports, but the source file parsing fails before the import can occur.

---

## Final Resolution

**Reverted to standard ISO installation approach** due to multiple provider limitations.

The ISO approach:
- Uses standard `.iso` files which Proxmox fully supports
- Attaches ISO as CD-ROM for installation
- Manual or kickstart-automated installation
- More reliable with current provider version

---

## Lessons Learned

1. **QCOW2 cloud images** are designed for cloud platforms (OpenStack, AWS, etc.) and have limited support in Proxmox Terraform providers.

2. **Directory-based storage** in Proxmox has different volume naming conventions that the bpg/proxmox provider struggles to parse.

3. **Standard ISO installation** is more reliable for Proxmox golden images, even if it requires more manual steps.

4. **Provider limitations** should be tested early when adopting new infrastructure patterns.

---

## Related Files

- Bootstrap scripts: `proxmox/bootstrap_proxmox/bootstrap.sh` (use `dev` or `prod` argument)
- Terraform config: `terraform/dev/proxmox/vms/golden-image/`
- AWS Secrets: `terraform/dev/aws/secrets/main.tf`
- Cleanup script: `proxmox/golden_templates/golden-vm-setup.sh`
