# Proxmox Virtual Machines

This directory contains Terraform modules for provisioning VMs on Proxmox.

## Modules

| Module | Description | Tags |
|--------|-------------|------|
| `golden-image` | Rocky Linux 10.1 golden image source VM (install from ISO) | `vm, golden, template, dev` |
| `freeipa` | FreeIPA identity management server | `vm, freeipa, identity, dev` |
| `k8s_masters` | Kubernetes control plane nodes (3 nodes) | `vm, k8s-master, kubernetes, dev` |
| `k8s_workers` | Kubernetes worker nodes (3 nodes) | `vm, k8s-worker, kubernetes, dev` |

## Golden Image Architecture

### Design Decision: Clone-Then-Template Approach

We use a **two-step golden image pattern** to maintain Terraform state consistency:

```
┌─────────────────────────────────────────────────────────────────┐
│  VM 9000 (Source)                                               │
│  - Created by Terraform                                         │
│  - Manually configured (OS install, hardening, cleanup)         │
│  - Stays as VM (stopped) → Terraform state remains valid        │
│  - Can be booted later for updates                              │
└─────────────────────────────────────────────────────────────────┘
                              │
                        qm clone 9000 9001
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  VM 9001 (Template)                                             │
│  - Clone of source VM                                           │
│  - Converted to template: qm template 9001                      │
│  - Referenced by freeipa, k8s_masters, k8s_workers              │
│  - NOT managed by Terraform (created manually)                  │
└─────────────────────────────────────────────────────────────────┘
```

### Why Not Packer?

We evaluated HashiCorp Packer but chose not to use it because:

1. **Complexity**: Packer requires additional tooling and learning curve
2. **Privileges**: Packer needs root/SSH access to Proxmox host, not just API token
3. **Critical Operation**: Image building is a sensitive operation that benefits from manual review
4. **Lab Environment**: For a homelab, the manual approach provides better visibility and control

### Why Not Direct Template Conversion?

If we converted VM 9000 directly to template:
- Terraform state would become invalid (VM no longer exists)
- Next `terraform apply` would try to recreate it
- Options like `terraform state rm` or `count = 0` add complexity

The clone approach keeps everything simple and state-consistent.

## Workflow Execution Order

### 1. Golden Image Setup (One-Time)

```bash
# Step 1: Run Terraform to create source VM
cd golden-image && terraform apply

# Step 2: Install OS via Proxmox console
# - Boot from ISO, install Rocky Linux 10.1
# - Configure network, install packages

# Step 3: Run cleanup/hardening script
ssh root@<vm-ip> 'bash -s' < /path/to/cleanup-script.sh

# Step 4: Shutdown and clone
qm shutdown 9000
qm clone 9000 9001 --name rocky10-golden-template --full

# Step 5: Convert clone to template
qm template 9001

# Done! VM 9000 stays as source, template 9001 is used for cloning
```

### 2. Infrastructure VMs (Cloned from Template 9001)

```bash
# Deploy in order:
cd freeipa && terraform apply      # Identity management first
cd k8s_masters && terraform apply  # Control plane
cd k8s_workers && terraform apply  # Worker nodes
```

### Updating the Golden Image

When you need to update the template (new packages, patches):

```bash
# Boot source VM
qm start 9000

# Make changes
ssh root@<vm-ip>
# ... update packages, etc.
poweroff

# Delete old template and create new one
qm destroy 9001
qm clone 9000 9001 --name rocky10-golden-template --full
qm template 9001
```

## Tags Convention

All VMs follow the tagging pattern: `[type, service, category, environment]`

- **type**: Resource type (`vm`)
- **service**: Service name (`freeipa`, `k8s-master`, `k8s-worker`, `golden`)
- **category**: Functional category (`identity`, `kubernetes`, `template`)
- **environment**: Deployment environment (`dev` or `prod`)

## Variable Structure

### Big Object Pattern (VM-specific config)
```hcl
variable "freeipa" {
  type = object({
    vmid, name, cores, memory, ip, gateway, vlan_id,
    startup_order, startup_delay, shutdown_delay,
    started, on_boot, stop_on_destroy
  })
}
```

### Map of Objects Pattern (multiple similar resources)
```hcl
variable "disks" {
  type = map(object({
    datastore_id, interface, size, ssd, discard, file_format
  }))
  default = {
    os_disk   = { ... }
    data_disk = { ... }
  }
}
```

## Hardcoded Values

Certain values are intentionally hardcoded in `main.tf` as infrastructure constants:

| Value | Location | Reason |
|-------|----------|--------|
| `full = true` | clone block | Full clone creates independent copy. Linked clones depend on source template - if template is deleted/modified, linked clones break. |
| `sockets = 1` | cpu block | Single socket is standard. Multi-socket requires specific licensing and is rarely needed. |
| `type = "host"` | cpu block | CPU passthrough gives best performance. Alternative `kvm64` is only needed for live migration across different CPU generations. |
| `username = "root"` | user_account | Cloud-init bootstrap user. Always root for initial provisioning, then Ansible creates service accounts. |
| `enabled = true` | agent block | QEMU guest agent is required for proper shutdown, IP detection, and guest commands. Always wanted. |
| `model = "virtio"` | network_device | VirtIO is the standard paravirtualized driver. E1000 is only for legacy OS without VirtIO support. |
| `device = "socket"` | serial_device | Serial console socket for `qm terminal` access. Standard configuration. |

**Rule of thumb**: Hardcode values that represent architectural decisions that would break things if accidentally changed.

## Lifecycle Configuration

### ignore_changes = [clone]

All VM modules that clone from the golden template include:

```hcl
lifecycle {
  ignore_changes = [clone]
}
```

**Why?** The `clone` block records the source template VM ID in Terraform state. If we change `template_vmid` (e.g., when creating a new template version), Terraform would see a mismatch and try to **destroy and recreate** existing VMs.

By ignoring clone changes:
- Existing VMs are protected from accidental destruction
- State keeps historical record of original clone source
- New VMs will use the updated template_vmid from config

## Module Outputs

| Module | Outputs |
|--------|---------|
| `golden-image` | vm_id, name, node, status, setup_instructions, clone_command |
| `freeipa` | vm_id, name, ip |
| `k8s_masters` | master1/2/3: vm_id, name, ip |
| `k8s_workers` | worker1/2/3: vm_id, name, ip |

## Environment Differences

Only `variables.tf` differs between dev and prod:

| Variable | Dev | Prod |
|----------|-----|------|
| `tags[3]` | `dev` | `prod` |
| `node_name` | `pve-dev` | `pve-prod` |
| `proxmox_api_url` | `https://pve-dev.lab.local:8006` | `https://pve-prod.lab.local:8006` |
| IP ranges | `10.0.6x.x` | `10.0.5x.x` |
| `disks.data_disk.datastore_id` | `nas-dev-data` | `nas-prod-data` |
| Resource sizing | Lower (2GB RAM, 2 cores) | Higher (4-8GB RAM, 4 cores) |
