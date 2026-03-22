# Proxmox LXC Containers

This directory contains Terraform modules for provisioning LXC containers on Proxmox.

## Modules

| Module | Description | Tags |
|--------|-------------|------|
| `ansible` | Ansible control node for configuration management | `lxc, ansible, automation, dev` |
| `golden-template` | Base LXC source container for creating template file | `lxc, golden, template, dev` |
| `local_runner` | CI/CD runner for local pipeline execution | `lxc, runner, cicd, dev` |
| `nginx` | Reverse proxy / load balancer | `lxc, nginx, proxy, dev` |
| `vault_cluster` | HashiCorp Vault HA cluster (3 nodes) | `lxc, vault, security, dev` |

## Golden Template Architecture

### Design Decision: Vzdump Template File Approach

LXC containers use a **template file** approach (different from VMs which clone from template ID):

```
┌─────────────────────────────────────────────────────────────────┐
│  LXC 9010 (Source Container)                                    │
│  - Created by Terraform                                         │
│  - Manually configured (packages, hardening)                    │
│  - Used to create template file via vzdump                      │
└─────────────────────────────────────────────────────────────────┘
                              │
                        vzdump + move
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  rocky-9-lxc-golden.tar.gz (Template File)                      │
│  - Stored at: nas-iso:vztmpl/rocky-9-lxc-golden.tar.gz          │
│  - Referenced by other LXC modules via template.file_id         │
│  - Source container can be destroyed after backup               │
└─────────────────────────────────────────────────────────────────┘
```

### Why Template File vs Clone?

**Critical Provider Limitation**: The Proxmox Terraform provider does NOT support SSH key or password injection when using the `clone` block for LXC containers. The `user_account` block (keys, password) only works with the `operating_system` block.

```hcl
# WORKS - operating_system block with template FILE
operating_system {
  template_file_id = "nas-iso:vztmpl/rocky-9-lxc-golden.tar.gz"
  type             = "centos"
}
initialization {
  user_account {
    keys     = var.ssh_public_keys   # ✓ Supported
    password = var.root_password     # ✓ Supported
  }
}

# FAILS - clone block (provider limitation)
clone {
  vm_id = 9002  # Clone from template container
}
initialization {
  user_account {
    keys     = var.ssh_public_keys   # ✗ NOT supported
    password = var.root_password     # ✗ NOT supported
  }
}
```

**Reference**: See `troubleshooting/proxmox/41-lxc-clone-vs-template-file-ssh-keys.md`

This means:
- We use vzdump template FILES (`.tar.gz`), not clone from container ID
- SSH keys are injected at container creation time via `user_account` block
- Ansible can reach containers immediately after deployment
- Source container can be destroyed after creating the template file
- `terraform state rm` is acceptable here (unlike VMs)

### Why Not Packer?

1. **Complexity**: Packer requires additional tooling and learning curve
2. **Privileges**: Packer needs root/SSH access to Proxmox host, not just API token
3. **Critical Operation**: Template creation is sensitive and benefits from manual review

## Workflow Execution Order

### 1. Golden Template Setup (One-Time)

```bash
# Step 1: Run Terraform to create source container
cd golden-template && terraform apply

# Step 2: Configure container
pct enter 9010
# Install packages, configure settings
exit

# Step 3: Stop and create backup
pct stop 9010
vzdump 9010 --compress gzip --storage local --mode stop

# Step 4: Move backup to template directory
mv /var/lib/vz/dump/vzdump-lxc-9010-*.tar.gz \
   /mnt/pve/nas-iso/template/cache/rocky-9-lxc-golden.tar.gz

# Step 5: Verify template is available
pveam list nas-iso

# Step 6: (Optional) Remove source container from TF state and destroy
terraform state rm proxmox_virtual_environment_container.lxc_golden
pct destroy 9010
```

### 2. Infrastructure Containers

```bash
cd ansible && terraform apply
cd local_runner && terraform apply
cd nginx && terraform apply
cd vault_cluster && terraform apply
```

## Tags Convention

All LXC containers follow the tagging pattern: `[type, service, category, environment]`

- **type**: Resource type (`lxc`)
- **service**: Service name (`ansible`, `nginx`, `vault`, etc.)
- **category**: Functional category (`automation`, `proxy`, `security`, etc.)
- **environment**: Deployment environment (`dev` or `prod`)

## Hardcoded Values

Certain values are intentionally hardcoded in `main.tf` as infrastructure constants:

| Value | Location | Reason |
|-------|----------|--------|
| `unprivileged = true` | container | Security best practice - container runs without root privileges on host |
| `nesting = true` | features | Required for running Docker/Podman inside the container |
| `name = "eth0"` | network_interface | Standard Linux network interface naming |
| `firewall = true` | network_interface | Enables Proxmox firewall integration for this interface |

**Rule of thumb**: Hardcode values that represent security or architectural decisions.

## Variable Structure

Each module uses consistent variable patterns:

```hcl
# Container-specific configuration (big object pattern)
variable "nginx" {
  type = object({
    ctid, name, cores, memory, ip, gateway, ...
  })
}

# Tags as separate variable for environment flexibility
variable "tags" {
  type    = list(string)
  default = ["lxc", "service", "category", "env"]
}

# Template file reference (not template ID like VMs)
variable "template" {
  type = object({
    file_id = string  # e.g., "nas-iso:vztmpl/rocky-9-lxc-golden.tar.gz"
    os_type = string
  })
}
```

## Module Outputs

All modules export minimal essential outputs:

| Output | Description |
|--------|-------------|
| `container_id` | Proxmox container ID (CTID) |
| `name` | Container hostname |
| `ip` | Container IP address |

## Environment Differences

Only `variables.tf` differs between dev and prod:

| Variable | Dev | Prod |
|----------|-----|------|
| `tags[3]` | `dev` | `prod` |
| `node_name` | `pve-dev` | `pve-prod` |
| `proxmox_api_url` | `https://pve-dev.lab.local:8006` | `https://pve-prod.lab.local:8006` |
| IP ranges | `10.0.6x.x` | `10.0.5x.x` |
