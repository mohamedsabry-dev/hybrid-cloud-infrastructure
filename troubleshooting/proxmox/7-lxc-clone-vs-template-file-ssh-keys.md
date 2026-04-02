# Case 7: LXC Clone vs Template File — SSH Key Injection

## Status: RESOLVED (Architecture Decision)
## Date: 2026-03-22
## Environment: Dev/Prod (pve-dev, pve-prod)
## Provider: bpg/proxmox

---

## Problem Statement

When deploying LXC containers, SSH key injection is required for Ansible reachability. The Proxmox Terraform provider has a critical limitation that affects how golden templates must be created.

---

## Root Cause

**Proxmox Terraform Provider Limitation**: The `user_account` block (SSH keys, password) is only supported when using the `operating_system` block, NOT the `clone` block.

| Deployment Method | `user_account` Support | SSH Keys | Password |
|-------------------|------------------------|----------|----------|
| `operating_system` + template FILE | **Yes** | Works | Works |
| `clone` from container ID | **No** | Fails | Fails |

### Error When Using Clone with user_account

```
Error: error updating container: received an HTTP 400 response - Reason: Parameter verification failed.
(ssh-public-keys: property is not defined in schema and the schema does not allow additional properties)
```

---

## Why This Matters

Without SSH key injection:
- Ansible cannot reach newly deployed containers
- Manual post-deploy SSH key setup required for each container
- Breaks Infrastructure as Code automation

---

## Solution: Use Vzdump Template Files

Instead of cloning from a template container, we use **vzdump template files** (`.tar.gz`):

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  LXC 9010 (Source Container)                                    │
│  - Created by Terraform from base Rocky Linux template          │
│  - Manually configured (packages, hardening, SSH setup)         │
│  - Used to create template file via vzdump                      │
└─────────────────────────────────────────────────────────────────┘
                              │
                        vzdump --compress gzip
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  rocky-9-lxc-golden.tar.gz (Template File)                      │
│  - Stored at: nas-iso:vztmpl/rocky-9-lxc-golden.tar.gz          │
│  - Used via operating_system.template_file_id                   │
│  - Supports user_account block with SSH keys                    │
└─────────────────────────────────────────────────────────────────┘
                              │
                        terraform apply
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  New LXC Container (ansible, nginx, vault, etc.)                │
│  - Created from template FILE (not cloned)                      │
│  - SSH keys injected via user_account block                     │
│  - Ansible reachable immediately                                │
└─────────────────────────────────────────────────────────────────┘
```

### Terraform Configuration

```hcl
# This WORKS - operating_system with template FILE
resource "proxmox_virtual_environment_container" "ansible" {
  # ...

  operating_system {
    template_file_id = "nas-iso:vztmpl/rocky-9-lxc-golden.tar.gz"
    type             = "centos"
  }

  initialization {
    hostname = var.ansible.name

    user_account {
      keys     = var.ssh_public_keys   # ✓ SSH keys injected
      password = var.root_password     # ✓ Password set
    }

    ip_config {
      ipv4 {
        address = var.ansible.ip
        gateway = var.ansible.gateway
      }
    }
  }
}
```

### Why NOT Clone Approach

```hcl
# This FAILS - clone block does NOT support user_account
resource "proxmox_virtual_environment_container" "ansible" {
  # ...

  clone {
    vm_id = 9002  # Template container ID
  }

  initialization {
    hostname = var.ansible.name

    user_account {
      keys     = var.ssh_public_keys   # ✗ NOT supported - API error
      password = var.root_password     # ✗ NOT supported - API error
    }
  }
}
```

---

## Template File Creation Workflow

```bash
# Step 1: Create source container from base template
cd terraform/dev/proxmox/lxc/golden-template
terraform apply

# Step 2: Configure container (packages, hardening)
pct enter 9010
# ... configure ...
exit

# Step 3: Stop and create backup
pct stop 9010
vzdump 9010 --compress gzip --storage local --mode stop

# Step 4: Move to template directory
mv /var/lib/vz/dump/vzdump-lxc-9010-*.tar.gz \
   /mnt/pve/nas-iso/template/cache/rocky-9-lxc-golden.tar.gz

# Step 5: Verify template available
pveam list nas-iso
```

---

## Key Differences: VMs vs LXC

| Aspect | VMs | LXC Containers |
|--------|-----|----------------|
| Golden Template | Clone from VM ID (9001) | Template FILE (.tar.gz) |
| Terraform Block | `clone { vm_id = 9001 }` | `operating_system { template_file_id = "..." }` |
| SSH Key Injection | Cloud-init (works with clone) | `user_account` (requires template file) |
| Source After Template | Keep (TF state consistency) | Can destroy (vzdump is backup) |

---

## References

- GitHub Issue #1905: [Error when cloning a container from a template containing ssh user key](https://github.com/bpg/terraform-provider-proxmox/issues/1905)
- GitHub Discussion #1879: [Stuck on LXC ssh key management](https://github.com/bpg/terraform-provider-proxmox/discussions/1879)
- Related: `troubleshooting/terraform/14-terraform-proxmox-lxc-clone-ssh-keys.md`

---

## Summary

| What | Decision |
|------|----------|
| LXC Template Approach | Vzdump template FILE (`.tar.gz`) |
| Why Not Clone | Provider limitation - no `user_account` support |
| SSH Key Injection | Works via `operating_system` block |
| Ansible Reachability | Immediate after container creation |
| Source Container | Can be destroyed after vzdump (unlike VMs) |
