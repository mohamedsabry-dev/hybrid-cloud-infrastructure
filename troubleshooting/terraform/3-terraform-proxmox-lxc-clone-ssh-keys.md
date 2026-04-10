# TS-TF-003 | 2026-02-23 | RESOLVED

## 1. Context
- System: Terraform with bpg/proxmox v0.96.0
- Environment: Dev/Prod (pve-dev, pve-prod)
- Related components: LXC clone operations, SSH key injection, user_account block, vzdump templates

## 2. Issue
- Symptom: When cloning an LXC container from a golden template, attempting to inject SSH keys or password via `user_account` block fails
- Error:
```
Error: error updating container: received an HTTP 400 response - Reason: Parameter verification failed.
(ssh-public-keys: property is not defined in schema and the schema does not allow additional properties)
```

Or for password:
```
Error: error updating container: received an HTTP 400 response - Reason: Parameter verification failed.
(password: property is not defined in schema and the schema does not allow additional properties)
```

**Why This Matters:**
- Ansible cannot reach newly deployed containers
- Manual post-deploy SSH key setup required for each container
- Breaks Infrastructure as Code automation

## 3. Analysis

### Part 1: Understanding the API Limitation

**Proxmox API Limitation** - Not a provider bug.

The Proxmox API handles LXC creation differently:

| Operation | API Method | SSH Keys / Password |
|-----------|------------|---------------------|
| Create from template (`operating_system` block) | POST | Supported |
| Clone existing container (`clone` block) | POST + PUT | **NOT Supported** |

When cloning, the provider:
1. **POST** - Clones the container (succeeds)
2. **PUT** - Updates container config with `user_account` values (fails)

The PUT endpoint does not accept `ssh-public-keys` or `password` parameters.

**Reference:**
- GitHub Issue #1905: [Error when cloning a container from a template containing ssh user key](https://github.com/bpg/terraform-provider-proxmox/issues/1905)
- GitHub Discussion #1879: [Stuck on LXC ssh key management](https://github.com/bpg/terraform-provider-proxmox/discussions/1879)

---

### Part 2: Configuration That Fails

**Golden Template (works - uses `operating_system`):**
```hcl
resource "proxmox_virtual_environment_container" "lxc_golden" {
  # ...

  operating_system {
    template_file_id = var.template_file
    type             = "centos"
  }

  initialization {
    hostname = var.lxc_container.hostname

    user_account {
      password = var.lxc_root_password
      keys     = []  # Works here
    }
    # ...
  }
}
```

**Cloned Container (fails - uses `clone`):**
```hcl
resource "proxmox_virtual_environment_container" "ansible" {
  # ...

  clone {
    datastore_id = var.disks.os_disk.datastore_id
    vm_id        = var.template_ctid
  }

  initialization {
    hostname = var.ansible.name

    user_account {
      password = var.root_password           # FAILS
      keys     = [var.local_runner_ssh_pubkey]  # FAILS
    }
    # ...
  }
}
```

---

### Part 3: Troubleshooting Attempts

**Attempt 1: Add `keys = []` placeholder to golden template**

Hypothesis: If the golden template has the `keys` schema defined, clones might inherit it.

```hcl
user_account {
  password = var.lxc_root_password
  keys     = []
}
```

Finding: Failed. The clone still cannot update SSH keys via API.

**Attempt 2: Add `username = "root"` to match VM behavior**

Hypothesis: LXC might need explicit username like VMs do.

```hcl
user_account {
  username = "root"
  password = var.lxc_root_password
  keys     = []
}
```

Finding: Failed with different error:
```
Error: Unsupported argument
An argument named "username" is not expected here.
```

LXC containers don't support `username` - it's always root.

**Attempt 3: Use placeholder SSH key in golden template**

Hypothesis: A valid SSH key format might work as placeholder.

```hcl
user_account {
  password = var.lxc_root_password
  keys     = ["ssh-ed25519 PLACEHOLDER_KEY_WILL_BE_REPLACED_IN_CLONES placeholder@golden-template"]
}
```

Finding: Failed:
```
Error: error creating container: received an HTTP 500 response - Reason: SSH public key validation error
```

Invalid SSH key format rejected by Proxmox.

**Attempt 4: Add `initialization` to `ignore_changes`**

Hypothesis: Prevent Terraform from attempting to update initialization settings after clone.

```hcl
lifecycle {
  ignore_changes = [
    started,
    description,
    initialization,
  ]
}
```

Finding: Would work, but rejected because:
- Changes to IP, hostname, etc. in Terraform won't apply to existing containers
- Reduces Infrastructure as Code benefits
- User preference to maintain full control

## 4. Root Cause
> Proxmox API limitation - not a provider bug. The PUT endpoint used for updating cloned containers does not accept `ssh-public-keys` or `password` parameters. Only the POST endpoint used for creating containers from template FILES supports these parameters.

| Deployment Method | `user_account` Support | SSH Keys | Password |
|-------------------|------------------------|----------|----------|
| `operating_system` + template FILE | **Yes** | Works | Works |
| `clone` from container ID | **No** | Fails | Fails |

## 5. Solution
> Use vzdump template FILES (`.tar.gz`) instead of cloning from container ID. This allows `operating_system` block which supports `user_account`.

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

### Working Terraform Configuration

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

### Template File Creation Workflow

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

## 6. Solution Risk
- Risk level: LOW
- Potential impact: Requires vzdump workflow for template creation instead of simple clone

## 7. Impact After Fix
- Observed: LXC containers deploy with SSH keys injected
- Ansible reachable immediately after container creation
- Full Infrastructure as Code maintained

**Summary:**

| What | Decision |
|------|----------|
| LXC Template Approach | Vzdump template FILE (`.tar.gz`) |
| Why Not Clone | Provider limitation - no `user_account` support |
| SSH Key Injection | Works via `operating_system` block |
| Ansible Reachability | Immediate after container creation |
| Source Container | Can be destroyed after vzdump (unlike VMs) |

## 8. Notes

### Key Differences: VMs vs LXC

| Aspect | VMs | LXC Containers |
|--------|-----|----------------|
| Golden Template | Clone from VM ID (9001) | Template FILE (.tar.gz) |
| Terraform Block | `clone { vm_id = 9001 }` | `operating_system { template_file_id = "..." }` |
| SSH Key Injection | Cloud-init (works with clone) | `user_account` (requires template file) |
| Source After Template | Keep (TF state consistency) | Can destroy (vzdump is backup) |

### Files Changed

- `terraform/dev/proxmox/lxc/golden-template/main.tf` - Added `keys = []` to `user_account`
- `terraform/dev/proxmox/lxc/ansible/main.tf` - Changed to `operating_system` block
- `terraform/dev/proxmox/lxc/local_runner/main.tf` - Changed to `operating_system` block
- `terraform/prod/proxmox/lxc/*/main.tf` - Same changes for prod

### Lessons Learned

1. **Proxmox API limitations** are not always obvious from Terraform error messages
2. **Clone vs Create** have different API capabilities in Proxmox
3. **GitHub Issues/Discussions** are valuable for understanding provider limitations
4. **Vzdump template files** are the correct approach for LXC golden images
5. **VMs and LXC differ** in how templates and SSH keys are handled

## 9. Workaround (if any)
> If vzdump approach not possible: Remove `user_account` from cloned containers and add SSH keys manually post-deploy via `ssh-copy-id` or direct file edit.

**Manual SSH Key Setup (fallback):**
```bash
# SSH into container (password from golden template)
ssh root@10.0.63.20

# Generate SSH key
ssh-keygen -t ed25519 -C "local-runner" -f ~/.ssh/id_ed25519 -N ""

# Copy to other containers
ssh-copy-id root@10.0.63.10
```
