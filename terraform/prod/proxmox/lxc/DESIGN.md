# Proxmox LXC — design notes

Why LXC containers use a different template pattern than VMs, and why. Current
state only; commands live in [`golden-template-operation-guide.txt`](golden-template-operation-guide.txt).

---

## Vzdump template file, not clone-from-ID

LXC containers clone from a **template file** (`.tar.gz` on the NAS ISO
storage), not from a template container ID. The chain is:

  LXC 9010 (source container, Terraform-managed)
    → vzdump → .tar.gz artifact
      → move to /mnt/pve/nas-iso/template/cache/rocky-9-lxc-golden.tar.gz
        → ansible / local_runner / nginx / vault_cluster reference this file_id

This is different from the VM pattern (which clones from template VMID 9001).
The difference is forced by a bpg/proxmox provider limitation, not a
preference.

## Why NOT clone-from-ID for LXC (the provider limitation)

The bpg/proxmox provider's `clone` block for LXC containers does NOT support
SSH key or password injection. The `user_account {}` block (keys, password)
only works in combination with the `operating_system {}` block — and
`operating_system` requires a template **file**, not a template container ID.

Concretely:

  operating_system {
    template_file_id = "nas-iso:vztmpl/rocky-9-lxc-golden.tar.gz"
    type             = "centos"
  }
  initialization {
    user_account {
      keys     = var.ssh_public_keys   # works
      password = var.root_password     # works
    }
  }

If I used `clone { vm_id = 9002 }` instead, `user_account` would be silently
ignored — SSH keys wouldn't be injected, and Ansible couldn't reach the new
containers.

Full TS reference: `troubleshooting/proxmox/41-lxc-clone-vs-template-file-ssh-keys.md`.

## Consequences of the template-file pattern

- SSH keys are injected at container creation time via `user_account` block
- Ansible can reach containers immediately after `terraform apply` — no
  manual key-distribution step
- The source container (9010) can be destroyed after the .tar.gz is written
  to the NAS — the template file is self-contained
- `terraform state rm` is acceptable for the source container (unlike VMs,
  where state continuity matters for template refresh)

## Why NOT Packer

Same reasoning as VMs — fleet-scale tool, overkill for a 2-laptop homelab.

## Hardcoded values in main.tf

- `unprivileged = true` — security best practice, container runs without root
  privileges on the host (the container's root maps to a non-privileged UID
  outside the container via the subuid range)
- `features.nesting = true` — required for running Docker/Podman inside the
  container (which local_runner and some vault-cluster tooling need)
- `network_interface.name = "eth0"` — Linux standard interface naming
- `network_interface.firewall = true` — enables Proxmox firewall integration
  per-interface

Rule of thumb: hardcode security and architectural decisions. Expose via
variables anything that could reasonably vary per environment or per
container.
