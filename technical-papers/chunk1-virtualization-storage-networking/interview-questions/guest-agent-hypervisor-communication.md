Guest Agent — Hypervisor-to-VM Runtime Communication
=====================================================

Question:
  What is qemu-guest-agent? How does it compare to VMware open-vm-tools?
  Is it related to cloud-init? What does each one do and when?

---

Two separate concepts:

  cloud-init = boot-time config delivery (IP, hostname, SSH keys)
  guest agent = runtime host-guest communication (freeze, shutdown, status)

  They are independent. Cloud-init works without guest agent.
  Guest agent works without cloud-init. Golden image installs both
  because they serve different purposes.

---

qemu-guest-agent (Proxmox/KVM):
  Installed inside the VM. Communicates with Proxmox via
  virtio-serial channel (not network — direct host-guest pipe).

  What it enables:
    - fs-freeze/fs-thaw for consistent backups (vzdump snapshot mode)
    - Graceful shutdown from Proxmox UI/API
    - IP address reporting to Proxmox (show VM IP in GUI)
    - File read/write from host to guest
    - Guest command execution from host

  Without it:
    - vzdump cannot freeze filesystem → backup may be crash-consistent
      only, not application-consistent
    - Proxmox can't see the VM's IP — shows blank in GUI
    - Graceful shutdown falls back to ACPI power button signal

---

open-vm-tools (VMware/FusionCompute):
  Same role as qemu-guest-agent but for VMware ecosystem.
  Communicates via VMware backdoor interface.

  What it enables:
    - Quiesced snapshots (same as fs-freeze)
    - Graceful shutdown from vCenter
    - IP/hostname reporting to vCenter
    - Customization spec delivery (THIS is the cloud-init datasource
      on VMware — open-vm-tools is the delivery channel)
    - Drag and drop, clipboard sharing (desktop VMs)

  Critical difference from qemu-guest-agent:
    On VMware, open-vm-tools also serves as the cloud-init datasource.
    Without it, cloud-init can't receive config from the hypervisor.
    On Proxmox, the datasource is a CD-ROM — independent of the agent.

---

Comparison:

  Feature                qemu-guest-agent        open-vm-tools
  Platform               Proxmox/KVM             VMware/FusionCompute
  Communication          virtio-serial channel    VMware backdoor
  Backup freeze          Yes (fs-freeze)          Yes (quiesced snapshot)
  Graceful shutdown      Yes                      Yes
  IP reporting           Yes                      Yes
  Cloud-init datasource  No (CD-ROM is separate)  Yes (tools IS the datasource)
  If missing             Backups less consistent   Backups less consistent
                         + no IP in GUI            + no IP in GUI
                                                   + cloud-init delivery broken

---

Why golden image installs both cloud-init and qemu-guest-agent:
  cloud-init: so Terraform can customize IP/hostname/SSH on creation
  qemu-guest-agent: so vzdump can fs-freeze for consistent backups
    and Proxmox can report VM status/IP and graceful shutdown

  Confirmed in: proxmox/golden_templates/golden-vm-setup.sh
