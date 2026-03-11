# Troubleshooting: Terraform Proxmox LXC Clone SSH Keys Issue

**Date:** 2026-02-23
**Environment:** Dev (pve-dev)
**Provider:** bpg/proxmox v0.96.0
**Proxmox Version:** 8.x

---

## Problem Statement

When cloning an LXC container from a golden template, attempting to inject SSH keys or password via `user_account` block fails with:

```
Error: error updating container: received an HTTP 400 response - Reason: Parameter verification failed.
(ssh-public-keys: property is not defined in schema and the schema does not allow additional properties)
```

Or for password:
```
Error: error updating container: received an HTTP 400 response - Reason: Parameter verification failed.
(password: property is not defined in schema and the schema does not allow additional properties)
```

---

## Root Cause

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

## Configuration That Fails

### Golden Template (works - uses `operating_system`)
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

### Cloned Container (fails - uses `clone`)
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

## Attempted Solutions

### Attempt 1: Add `keys = []` placeholder to golden template
**Hypothesis:** If the golden template has the `keys` schema defined, clones might inherit it.

**Change:**
```hcl
# Golden template
user_account {
  password = var.lxc_root_password
  keys     = []
}
```

**Result:** Failed. The clone still cannot update SSH keys via API.

---

### Attempt 2: Add `username = "root"` to match VM behavior
**Hypothesis:** LXC might need explicit username like VMs do.

**Change:**
```hcl
user_account {
  username = "root"
  password = var.lxc_root_password
  keys     = []
}
```

**Result:** Failed with different error:
```
Error: Unsupported argument
An argument named "username" is not expected here.
```

LXC containers don't support `username` - it's always root.

---

### Attempt 3: Use placeholder SSH key in golden template
**Hypothesis:** A valid SSH key format might work as placeholder.

**Change:**
```hcl
user_account {
  password = var.lxc_root_password
  keys     = ["ssh-ed25519 PLACEHOLDER_KEY_WILL_BE_REPLACED_IN_CLONES placeholder@golden-template"]
}
```

**Result:** Failed:
```
Error: error creating container: received an HTTP 500 response - Reason: SSH public key validation error
```

Invalid SSH key format rejected by Proxmox.

---

### Attempt 4: Add `initialization` to `ignore_changes`
**Hypothesis:** Prevent Terraform from attempting to update initialization settings after clone.

**Change:**
```hcl
lifecycle {
  ignore_changes = [
    started,
    description,
    initialization,
  ]
}
```

**Result:** Would work, but rejected because:
- Changes to IP, hostname, etc. in Terraform won't apply to existing containers
- Reduces Infrastructure as Code benefits
- User preference to maintain full control

---

## Final Solution

**Remove `user_account` from cloned containers entirely.**

### Golden Template (keeps `user_account`)
```hcl
# terraform/dev/proxmox/lxc/golden-template/main.tf

initialization {
  hostname = var.lxc_container.hostname

  user_account {
    password = var.lxc_root_password
    keys     = []
  }

  ip_config { ... }
  dns { ... }
}
```

### Cloned Containers (no `user_account`)
```hcl
# terraform/dev/proxmox/lxc/ansible/main.tf
# terraform/dev/proxmox/lxc/local_runner/main.tf

initialization {
  hostname = var.ansible.name

  # NO user_account block - inherited from golden template

  ip_config {
    ipv4 {
      address = var.ansible.ip
      gateway = var.ansible.gateway
    }
  }

  dns {
    servers = var.dns_servers
    domain  = var.search_domain
  }
}
```

### Post-Deploy: Manual SSH Key Setup

**For local_runner LXC (10.0.63.20):**
```bash
# SSH into local_runner (password from golden template)
ssh root@10.0.63.20

# Generate SSH key
ssh-keygen -t ed25519 -C "local-runner" -f ~/.ssh/id_ed25519 -N ""

# View public key
cat ~/.ssh/id_ed25519.pub

# Store in AWS Secrets Manager (for documentation)
aws secretsmanager put-secret-value \
  --secret-id dev/local-runner/ssh-public-key \
  --secret-string "$(cat ~/.ssh/id_ed25519.pub)"
```

**For ansible LXC (10.0.63.10):**
```bash
# From local_runner, copy SSH key to ansible
ssh-copy-id root@10.0.63.10

# Or manually on ansible:
ssh root@10.0.63.10
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo "ssh-ed25519 AAAA... local-runner" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

---

## Summary

| What | Status |
|------|--------|
| SSH keys via `clone` block | Not supported (Proxmox API limitation) |
| Password via `clone` block | Not supported (Proxmox API limitation) |
| SSH keys via `operating_system` block | Works |
| Password via `operating_system` block | Works |
| Workaround | Remove `user_account` from clones, add keys manually |

---

## Files Changed

- `terraform/dev/proxmox/lxc/golden-template/main.tf` - Added `keys = []` to `user_account`
- `terraform/dev/proxmox/lxc/ansible/main.tf` - Remove `user_account` block
- `terraform/dev/proxmox/lxc/local_runner/main.tf` - Remove `user_account` block
- `terraform/prod/proxmox/lxc/golden-template/main.tf` - Added `keys = []` to `user_account`
- `terraform/prod/proxmox/lxc/ansible/main.tf` - Remove `user_account` block
- `terraform/prod/proxmox/lxc/local_runner/main.tf` - Remove `user_account` block
- `.github/workflows/dev-ansible.yml` - Remove SSH key fetch (not needed)
- `.github/workflows/dev-local_runner.yml` - Remove password fetch (not needed)
- `.github/workflows/prod-ansible.yml` - Remove SSH key fetch (not needed)
- `.github/workflows/prod-local_runner.yml` - Remove password fetch (not needed)

---

## Lessons Learned

1. **Proxmox API limitations** are not always obvious from Terraform error messages
2. **Clone vs Create** have different API capabilities in Proxmox
3. **GitHub Issues/Discussions** are valuable for understanding provider limitations
4. **Manual post-deploy steps** are sometimes necessary for API limitations
