# TS-TF-001 | 2026-02 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Terraform / Proxmox
Sub-techs: Terraform bpg/proxmox provider, QCOW2 cloud images, cloud-init,
           Proxmox storage, golden image
Environment: DEV | Proxmox VE pve-dev | Rocky Linux 10.1 golden image
Re-opened: No

_____________________________________________________________________

[Issue Description]
Multiple errors when setting up golden image VM using QCOW2 cloud images via
Terraform bpg/proxmox provider. Issues spanned storage configuration, permissions,
daemon state, and fundamental provider limitations with QCOW2 imports.

Final resolution: reverted to standard ISO installation approach due to multiple
provider limitations with QCOW2 cloud images.

_____________________________________________________________________

[Analysis]

# Initial Check Notes:

Issue 1 — Snippets content type not enabled:
  Error: error creating file: received an HTTP 500 response
  storage 'local' does not support content-type 'snippets'

  Fix:
    mkdir -p /var/lib/vz/snippets
    /usr/sbin/pvesm set local --content backup,iso,vztmpl,snippets

Issue 2 — pvesm command not found:
  Error: -bash: pvesm: command not found
  Fix: use full path /usr/sbin/pvesm or run as root.

Issue 3 — Permission denied writing snippets:
  Error: error creating file: failed to upload file - permission denied
  Fix:
    chown root:admin_dev /var/lib/vz/snippets
    chmod 775 /var/lib/vz/snippets

Issue 4 — ipcc_send_rec failed:
  Error: creating custom disk: ipcc_send_rec[1] failed: Unknown error -1
  Fix:
    systemctl restart pvedaemon pveproxy pvestatd

Issues 5-7 — Unable to parse directory volume name:
  Error: creating custom disk: unable to parse directory volume name
  'iso/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2'

  Finding: provider cannot parse directory-based storage volume names
  (local, NFS, CIFS) for QCOW2 imports. Provider expects specific volume
  name formats, not arbitrary filenames in directory storage.

Issue 8 — Download file wrong extension:
  Error: error download file by URL: received an HTTP 400 response - wrong file extension

  Finding: Proxmox rejects .qcow2 for iso content type. Provider validates
  file extensions against content types — QCOW2 and iso are incompatible.


# Suspected Root Cause
bpg/proxmox Terraform provider (v0.93.1) has fundamental limitations with
QCOW2 cloud images:
  1. Cannot parse directory-based storage volume names for disk imports
  2. download_file resource validates extensions against content types
  3. Provider expects specific volume name formats, not arbitrary filenames

QCOW2 cloud images are designed for cloud platforms (OpenStack, AWS) and have
limited Proxmox Terraform provider support.


# More Checks Notes:
Attempted workaround via manual qm importdisk as root — can import QCOW2
successfully but the disk is not managed by Terraform state. Not viable
for infrastructure-as-code approach.


# Suspected Solution
Revert to standard ISO installation approach — ISO files are fully supported
by Proxmox and have no provider limitations.


# Test
Golden image created via ISO attach + Rocky Linux installation.
VMs cloned from resulting template successfully.

Result: PASS — no provider errors, template functional.

_____________________________________________________________________

[Final Root Cause]
bpg/proxmox provider v0.93.1 cannot handle QCOW2 cloud image imports via
directory-based storage. Volume name parsing fails for local/NFS/CIFS storage
types. Extension validation rejects .qcow2 for iso content type. Combination
of provider limitations made QCOW2-based golden image creation unviable via
Terraform at this provider version.

_____________________________________________________________________

[Final Solution]
Reverted to standard ISO installation approach for golden image creation.

ISO approach advantages over QCOW2:
  Standard .iso files fully supported by Proxmox and bpg/proxmox provider.
  Attaches ISO as CD-ROM for installation.
  Compatible with kickstart automation.
  No volume name parsing or extension validation issues.

Related files:
  proxmox/bootstrap_proxmox/bootstrap.sh
  terraform/dev/proxmox/vms/golden-image/
  proxmox/golden_templates/golden-vm-setup.sh

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: ISO installation requires more manual steps than cloud images but has
no provider compatibility issues.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Lessons learned:
  1. QCOW2 cloud images are designed for cloud platforms — limited Proxmox
     Terraform provider support at current version
  2. Directory-based storage (local, NFS, CIFS) in Proxmox has different volume
     naming conventions that the provider cannot parse for disk imports
  3. Standard ISO installation is more reliable for Proxmox golden images
  4. Test provider limitations early when adopting new patterns — don't build
     full workflow before validating the core import mechanism

If QCOW2 import is needed outside Terraform:
  qm importdisk <vmid> <image.qcow2> <storage>  (as root, manual, not in state)