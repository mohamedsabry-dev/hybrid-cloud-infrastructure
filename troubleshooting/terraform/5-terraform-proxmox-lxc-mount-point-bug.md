# TS-TF-005 | 2026-03 | RESOLVED
_____________________________________________________________________

[Info]
Author:
Domain: Terraform / Proxmox
Sub-techs: Terraform bpg/proxmox provider, LXC mount_point, NFS storage,
           provider bug, provider mirror, local runner
Environment: DEV | pve-dev | Ansible LXC (CTID 2001) | NFS nas-dev-data
             Terraform 1.14.3, bpg/proxmox initially 0.93.1
Re-opened: No

_____________________________________________________________________

[Issue Description]
bpg/proxmox Terraform provider fails to create or track mount_points on LXC
containers — silent failure with perpetual drift.

Observed behaviour:
  1. mount_point not created — after apply, container has no mount point in Proxmox
  2. State shows empty — tfstate has "mount_point": [] despite config defining it
  3. Perpetual replacement — every plan shows container must be replaced
  4. Silent failure — apply reports success, no errors, mount_point simply absent

  Terraform plan output:
  -/+ resource "proxmox_virtual_environment_container" "ansible" must be replaced
      + mount_point { # forces replacement
          + path   = "/opt/ansible"
          + size   = "5G"
          + volume = "nas-dev-data"
        }

  tfstate before fix: "mount_point": []  (empty despite config having mount_point)

_____________________________________________________________________

[Analysis]

# Initial Check Notes:

Attempt 1 — Check if NFS storage type is the issue:
  Manual creation as root:
    pct set 2001 -mp0 nas-dev-data:5,mp=/opt/ansible
    Formatting '/mnt/pve/nas-dev-data/images/2001/vm-2001-disk-0.raw'...
  Result: works. NFS storage supports mount_points.
  Finding: not a storage type issue.

Attempt 2 — Try local-lvm instead:
  Changed volume = "local-lvm" in variables.tf.
  Same issue — mount_point not created, state empty.
  Finding: not storage-specific.

Attempt 3 — Check API token permissions:
  Non-root user test:
    admin_dev@pve-dev:~$ pct set 2001 -mp0 nas-dev-data:6,mp=/opt/ansible2
    ipcc_send_rec[1] failed: Unknown error -1
    Unable to load access control list: Unknown error -1
  Finding: non-root cannot create mount_points. But this was NOT the root
  cause — the provider was not even attempting the API call.

Attempt 4 — Reference existing pre-created volume:
  Manually created volume, got its name (local-lvm:vm-2001-disk-1),
  referenced it in Terraform.
  Same issue — mount_point not in state, triggers replacement.

Attempt 5 — ignore_changes lifecycle:
  lifecycle { ignore_changes = [mount_point] }
  Would work as a workaround but not a real solution — loses IaC control.

Root cause discovery — found via GitHub Issues:

  Issue #1392 — mount_point implementation broken:
  https://github.com/bpg/terraform-provider-proxmox/issues/1392
  Maintainer: "The schema does not have the actual mount point name (mp0, mp1)
  attribute, so the provider does not know which list item belongs to which
  mount point."
  Status: postponed to v2.0 milestone.

  Issue #2507 — regression in 0.93.0:
  https://github.com/bpg/terraform-provider-proxmox/issues/2507
  Adding mount_points to cloned containers forces replacement instead of
  in-place update.
  Fix: merged in PR #2529, released in v0.94.0.
  Commit: fix(lxc): provision mount points when cloning containers (67990d7)


# Suspected Root Cause
Provider bug in version 0.93.x. mount_point schema lacks the mount point name
(mp0, mp1) attribute — provider does not know which list item belongs to which
mount point. Regression introduced in 0.93.0 forces container replacement instead
of in-place update. Fixed in v0.94.0+ via PR #2529.


# More Checks Notes:
N/A — GitHub issues confirmed exact root cause and fix version.


# Suspected Solution
Upgrade bpg/proxmox provider from 0.93.1 to 0.96.0 (confirmed stable, contains fix).


# Test
Upgraded provider, removed existing manual mount point, re-ran plan and apply.

Command:
  pct set 2001 -delete mp0
  terraform init -upgrade
  terraform plan -out=tfplan && terraform apply tfplan

  pct config 2001 | grep mp0
  df -h /opt/ansible  (inside container)

Result: PASS
  pct config: mp0: nas-dev-data:2001/vm-2001-disk-0.raw,mp=/opt/ansible,size=5G
  df: /dev/sdb  5.0G  68K  5.0G  1%  /opt/ansible

  tfstate after fix:
    mount_point[0]:
      path: /opt/ansible
      path_in_datastore: nas-dev-data:2001/vm-2001-disk-0.raw
      size: 5G
      volume: nas-dev-data:2001/vm-2001-disk-0.raw

_____________________________________________________________________

[Final Root Cause]
bpg/proxmox provider 0.93.x has a known regression (issue #2507) where
mount_point schema lacks the mount point name (mp0, mp1) attribute. Provider
cannot determine which list item belongs to which mount point. In 0.93.0,
adding mount_points to cloned containers forces replacement instead of in-place
update. No error is surfaced — apply reports success while silently failing to
create the mount point. Fixed in v0.94.0 via PR #2529.

_____________________________________________________________________

[Final Solution]
Upgraded bpg/proxmox provider from 0.93.1 to 0.96.0 in all providers.tf files.

  # Before
  version = "0.93.1"   # buggy

  # After
  version = "0.96.0"   # fixed (issue #2507 resolved in 0.94.0)

Files updated:
  terraform/dev/proxmox/vms/freeipa/providers.tf
  terraform/dev/proxmox/vms/golden-image/providers.tf
  terraform/dev/proxmox/lxc/ansible/providers.tf
  terraform/dev/proxmox/lxc/golden-template/providers.tf
  terraform/prod/proxmox/vms/freeipa/providers.tf
  terraform/prod/proxmox/vms/golden-image/providers.tf
  terraform/prod/proxmox/lxc/ansible/providers.tf
  terraform/prod/proxmox/lxc/golden-template/providers.tf

Provider mirror update (Mac Mini self-hosted runner):
  cd ~/.terraform.d/providers-mirror
  mkdir -p registry.terraform.io/bpg/proxmox/0.96.0/darwin_arm64
  cd registry.terraform.io/bpg/proxmox/0.96.0/darwin_arm64
  curl -LO https://github.com/bpg/terraform-provider-proxmox/releases/download/v0.96.0/terraform-provider-proxmox_0.96.0_darwin_arm64.zip
  unzip terraform-provider-proxmox_0.96.0_darwin_arm64.zip
  rm terraform-provider-proxmox_0.96.0_darwin_arm64.zip

Updated runner docs: github/runner-mac-mini.md → bpg/proxmox v0.96.0

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: Provider upgrade may introduce other behaviour changes.
Always test in dev before applying to prod.

_____________________________________________________________________

[References]
- https://github.com/bpg/terraform-provider-proxmox/issues/1392
- https://github.com/bpg/terraform-provider-proxmox/issues/2507
- https://github.com/bpg/terraform-provider-proxmox/pull/2529

_____________________________________________________________________

[Draft Notes]

Provider version history for mount_point:
  < 0.93.0  worked (with double-apply workaround)
  0.93.0    regression — forces replacement (issue #2507)
  0.93.1    still broken
  0.94.0    FIXED — PR #2529 merged
  0.96.0    current stable, confirmed working

Key lessons:
  1. Provider bugs happen — always check GitHub issues when Terraform behaves
     unexpectedly and silently (apply succeeds but change does not take effect)
  2. Version matters — 0.93.x had broken mount_point, fixed in 0.94.0+
  3. Manual pct set testing helped isolate that the issue was not storage or
     permissions — the provider was not even making the API call
  4. Self-hosted runners with provider mirrors require manual version updates
  5. Silent success is harder to debug than an error — check state and Proxmox
     directly after apply, do not trust apply output alone

Workaround (if upgrade not possible):
  lifecycle { ignore_changes = [mount_point] }
  Create mount points manually: pct set <ctid> -mp0 <storage>:<size>,mp=<path>

Related files:
  terraform/dev/proxmox/lxc/ansible/
  $HOME/.terraform.d/providers-mirror
  github/runner-mac-mini.md