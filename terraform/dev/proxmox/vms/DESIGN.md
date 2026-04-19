# Proxmox VMs — design notes

Why the VM modules in this folder are shaped the way they are. Current state
only; commands live in [`golden-image-operation-guide.txt`](golden-image-operation-guide.txt).

---

## Clone-then-template pattern

VMs are deployed by cloning a template VMID (9001), not by running the OS
installer each time. The chain is:

  9000 (source VM, Terraform-managed, stopped)
    → qm clone 9000 9001
      → qm template 9001 (template, NOT Terraform-managed)
        → freeipa, k8s_masters, k8s_workers clone from 9001

**Why the source (9000) stays as a VM and not a template:**
If I converted 9000 directly into a template, Terraform state would become
invalid (VM no longer exists) and the next `apply` would try to recreate it.
Options like `terraform state rm` or `count = 0` solve it with extra moving
parts. Keeping 9000 as a stopped VM keeps Terraform state consistent and lets
me boot it again for updates.

**Why 9001 is NOT in Terraform state:**
It's a one-shot conversion of a clone — adopting it into Terraform would
require a shared-state model with the source VM that's more trouble than
value. Template 9001 is managed manually (shell commands in the guide);
that's an acceptable tradeoff for the once-in-a-while template-refresh
workflow.

## Why not Packer

Packer is the right answer at fleet scale. For a 2-laptop homelab, manual
clone-then-template is fine and avoids another tool in the stack.

## Hardcoded values in main.tf

Certain values are deliberately hardcoded rather than exposed as variables —
they represent architectural decisions that would break the VM if changed:

- `full = true` on `clone` — full clone creates an independent disk. Linked
  clones depend on the source template staying around and matching; if the
  template is deleted or replaced, linked clones break.
- `sockets = 1` — multi-socket CPU config needs specific licensing and is
  rarely useful for a lab VM.
- `cpu.type = "host"` — CPU passthrough gives best performance. Alternative
  `kvm64` is only needed for live migration across different CPU generations,
  which I don't do.
- `agent.enabled = true` — QEMU guest agent is required for proper shutdown,
  IP detection, and guest commands. Without it, `qm shutdown` doesn't work
  gracefully.
- `network_device.model = "virtio"` — VirtIO paravirtualized driver is the
  standard. E1000 is only for legacy OS without VirtIO support.
- `serial_device.device = "socket"` — serial console socket enables
  `qm terminal` for out-of-band access.

Rule of thumb: hardcode values that represent architectural decisions that
would break things if accidentally changed. Expose via variables anything
that could reasonably vary per environment or per VM.

## lifecycle ignore_changes = [clone]

All VM modules that clone from 9001 include:

  lifecycle {
    ignore_changes = [clone]
  }

The `clone` block records the source template's VMID in state. If the
template is refreshed and the old one is replaced (same VMID 9001, different
contents), without `ignore_changes` Terraform would see a "template changed"
mismatch and try to destroy + recreate every VM that clones from it.

`ignore_changes = [clone]` tells Terraform: "once this VM is created, don't
re-evaluate what it cloned from." Existing VMs are protected from accidental
destruction. New VMs created by a future `apply` will still pick up the
current template_vmid from config.

Trade-off: state no longer reflects the live clone-source relationship. I
can't use state to answer "what template was this cloned from?" — I have to
look at the VM's actual disk history. That's fine for my workflow.
