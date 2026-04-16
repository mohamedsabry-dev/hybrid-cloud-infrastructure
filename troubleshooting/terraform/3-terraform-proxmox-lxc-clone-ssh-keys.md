# TS-TF-003 | 2026-02-23 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Terraform / Proxmox
Sub-techs: Terraform bpg/proxmox provider, LXC clone, operating_system block,
           user_account, SSH key injection, vzdump templates
Environment: DEV & PROD | pve-dev, pve-prod | bpg/proxmox v0.96.0
Re-opened: No

_____________________________________________________________________

[Issue Description]
When cloning an LXC container from a golden template, attempting to inject SSH
keys or password via user_account block fails. Ansible cannot reach newly
deployed containers. Manual post-deploy SSH key setup required — breaks IaC.

  Error (SSH keys):
  error updating container: received an HTTP 400 response
  ssh-public-keys: property is not defined in schema and the schema does not
  allow additional properties

  Error (password):
  error updating container: received an HTTP 400 response
  password: property is not defined in schema and the schema does not allow
  additional properties

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Proxmox API handles LXC creation differently depending on the operation:

  Operation                        API method   SSH keys / password
  Create from template file        POST         SUPPORTED
  Clone from existing container    POST + PUT   NOT SUPPORTED

When cloning, the provider:
  1. POST — clones the container (succeeds)
  2. PUT — updates container config with user_account values (FAILS)

The PUT endpoint does not accept ssh-public-keys or password parameters.
This is a Proxmox API limitation, not a provider bug.

Reference: GitHub Issue #1905 — Error when cloning a container from a template
containing ssh user key (bpg/terraform-provider-proxmox)

Configuration that fails (uses clone block):
  clone {
    datastore_id = var.disks.os_disk.datastore_id
    vm_id        = var.template_ctid
  }
  initialization {
    user_account {
      password = var.root_password         ← FAILS
      keys     = [var.ssh_pubkey]          ← FAILS
    }
  }

Configuration that works (uses operating_system block):
  operating_system {
    template_file_id = var.template_file
    type             = "centos"
  }
  initialization {
    user_account {
      password = var.lxc_root_password     ← WORKS
      keys     = []                        ← WORKS
    }
  }


# Suspected Root Cause
Proxmox API limitation — PUT endpoint for cloned container updates does not
accept ssh-public-keys or password. Only the POST endpoint for creating
containers from template FILES supports these parameters.


# More Checks Notes:

Attempt 1 — Add keys = [] placeholder to golden template:
  Hypothesis: if golden template has keys schema defined, clones might inherit it.
  Result: Failed. Clone still cannot update SSH keys via PUT.

Attempt 2 — Add username = "root" to match VM behaviour:
  Result: Error: Unsupported argument. LXC containers do not support username
  field — it is always root. Only VMs support username in user_account.

Attempt 3 — Use placeholder SSH key in golden template:
  keys = ["ssh-ed25519 PLACEHOLDER_KEY_WILL_BE_REPLACED_IN_CLONES placeholder@golden"]
  Result: HTTP 500 — SSH public key validation error. Invalid key format rejected.

Attempt 4 — Add initialization to ignore_changes lifecycle:
  lifecycle { ignore_changes = [started, description, initialization] }
  Result: Would technically work, but rejected — changes to IP, hostname, etc.
  in Terraform would no longer apply to existing containers. Loses IaC benefits.


# Suspected Solution
Use vzdump template files (.tar.gz) instead of cloning from container ID.
This uses the operating_system block which supports user_account with SSH keys.


# Test
Changed all LXC container configurations to use operating_system block with
vzdump template file. Deployed containers and verified Ansible connectivity.

Result: PASS — SSH keys injected, Ansible reachable immediately after creation.

_____________________________________________________________________

[Final Root Cause]
Proxmox API limitation. The PUT endpoint used to update cloned containers does
not accept ssh-public-keys or password parameters. Only the POST endpoint used
when creating containers from template FILES supports these parameters. The
bpg/proxmox provider correctly uses clone → POST + PUT which hits this API
limitation. Using operating_system → POST bypasses it entirely.

  Deployment method                  user_account   SSH keys   Password
  operating_system + template file   YES            Works      Works
  clone from container ID            NO             Fails      Fails

_____________________________________________________________________

[Final Solution]
Use vzdump template files (.tar.gz) for all LXC golden image deployments
instead of cloning from container IDs.

Template file creation workflow:
  # 1. Create source container from base template
  cd terraform/dev/proxmox/lxc/golden-template && terraform apply

  # 2. Configure container (packages, hardening, SSH setup)
  pct enter 9010 && <configure> && exit

  # 3. Stop and create vzdump backup
  pct stop 9010
  vzdump 9010 --compress gzip --storage local --mode stop

  # 4. Move to template directory
  mv /var/lib/vz/dump/vzdump-lxc-9010-*.tar.gz \
     /mnt/pve/nas-iso/template/cache/rocky-9-lxc-golden.tar.gz

  # 5. Verify template available
  pveam list nas-iso

Working Terraform configuration (operating_system block):
  operating_system {
    template_file_id = "nas-iso:vztmpl/rocky-9-lxc-golden.tar.gz"
    type             = "centos"
  }
  initialization {
    hostname = var.ansible.name
    user_account {
      keys     = var.ssh_public_keys    ← works
      password = var.root_password      ← works
    }
    ip_config {
      ipv4 { address = var.ansible.ip; gateway = var.ansible.gateway }
    }
  }

Files changed:
  terraform/dev/proxmox/lxc/golden-template/main.tf
  terraform/dev/proxmox/lxc/ansible/main.tf
  terraform/dev/proxmox/lxc/local_runner/main.tf
  terraform/prod/proxmox/lxc/*/main.tf

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: Requires vzdump workflow for template creation instead of simple clone.
Source container (9010) can be destroyed after vzdump — unlike VMs where
source must be kept for Terraform state consistency.

_____________________________________________________________________

[References]
- https://github.com/bpg/terraform-provider-proxmox/issues/1905

_____________________________________________________________________

[Draft Notes]

VMs vs LXC differences in Terraform:

  Aspect              VMs                              LXC Containers
  Golden template     clone { vm_id = 9001 }           operating_system { template_file_id = ... }
  SSH key injection   cloud-init (works with clone)     user_account (requires template file)
  Source after tmpl   Keep (Terraform state)            Can destroy (vzdump is a backup)
  Template format     VM disk                           .tar.gz file

Key lessons:
  1. Proxmox API limitations are not always obvious from Terraform error messages
  2. Clone and create have different API capabilities — clone uses PUT which
     does not support SSH keys or password
  3. GitHub Issues/Discussions are valuable for understanding provider limitations
  4. vzdump template files are the correct LXC golden image approach
  5. VMs and LXC differ fundamentally in how templates and SSH keys are handled

Workaround if vzdump not possible:
  Remove user_account from cloned containers.
  Add SSH keys manually post-deploy:
    ssh root@<container-ip>
    ssh-keygen -t ed25519 -C "label" -f ~/.ssh/id_ed25519 -N ""
    ssh-copy-id root@<target>