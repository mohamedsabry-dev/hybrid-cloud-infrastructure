Cloud-Init — Datasources, Metadata, and Cross-Platform Behavior
=================================================================

Question:
  What do you know about cloud-init? How do you use it in your
  environment? How does its behavior compare across on-prem and cloud?
  Why do you even need it?

---

Why cloud-init exists:
  You want one golden image that becomes 50 different VMs — each with
  its own IP, hostname, SSH keys, users. Cloud-init is the agent inside
  the VM that reads "who am I?" config from the hypervisor/cloud on
  every boot and applies it. Without it, every VM needs manual config
  or a separate image per identity.

---

How it works — 3 stages:
  init stage:  network config, hostname, SSH keys, disk resize, mounts
  config stage: packages, repos, timezone, users
  final stage:  user-data scripts, phone-home, final message

  Runs once on first boot (PER_INSTANCE) or every boot depending on
  the module. Network config runs every boot by default — that's why
  manual edits get overwritten.

---

Datasource comparison — how cloud-init gets its config:

  Proxmox (my environment):
    Terraform creates VM → Proxmox burns a small ISO with the config
    → attached as IDE CD-ROM on ide2 (media=cdrom, ~300KB)
    → cloud-init reads from the CD-ROM on boot
    → applies static IP, hostname, SSH keys
    → config file: /etc/NetworkManager/system-connections/cloud-init-eth0.nmconnection
    → method=manual, address1=10.0.50.10/24
    → CD-ROM stays attached — if you change settings in Proxmox/Terraform,
      VM picks them up on next boot

  AWS EC2:
    Instance launches → AWS writes config to metadata service
    → cloud-init calls http://169.254.169.254/latest/meta-data/
    → gets hostname, IP, SSH keys, IAM role, user-data
    → 169.254.169.254 is link-local, intercepted at hypervisor level
    → never leaves the host
    → network config: BOOTPROTO=dhcp (VPC DHCP assigns the IP)
    → IP is "static" from AWS perspective but delivered via DHCP to the OS

  FusionCompute (Huawei, from TAC):
    Admin sets IP in FusionCompute GUI → writes customization spec
    → cloud-init inside VM reads via open-vm-tools (vmtoolsd)
    → applies network config on boot
    → WITHOUT open-vm-tools installed → datasource is broken
      → cloud-init can't read from FusionCompute → applies empty config

---

IMDSv1 vs IMDSv2 (EC2 metadata security):

  IMDSv1: plain curl, no auth. Any process on the instance can read
  metadata including IAM role credentials. SSRF vulnerability = attacker
  tricks your app into curling 169.254.169.254 and stealing credentials.
  Real-world: Capital One breach 2019, exactly this attack path.

  IMDSv2: token-based. Must PUT to get a token first, then pass it
  in header on every request. Stops SSRF because most SSRF can do GET
  but cannot do PUT or add custom headers.

  My setup: http_tokens=required in Terraform → IMDSv1 completely
  disabled. Plain curl returns nothing. Must use:
    TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
      -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    curl -H "X-aws-ec2-metadata-token: $TOKEN" \
      http://169.254.169.254/latest/meta-data/local-ipv4

---

The 99-disable file and cloud-init control:

  /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
  Contains: network: {config: disabled}
  Tells cloud-init to stop managing networking → manual config survives reboots.

  Key detail: the value must be "disabled" not "disable" — typo makes
  cloud-init ignore the directive and stay active.

---

TAC story — FusionCompute cloud-init trap (Huawei):

  Customer installed VM from image on FusionCompute. VM booted with
  no network config every time. Manual config via nmcli worked but
  disappeared on reboot. Editing IP from FusionCompute GUI (VM up
  or down) also did nothing.

  Root cause — two bugs in the image, one masking the other:
    Bug 1: open-vm-tools not installed → cloud-init couldn't read
      FusionCompute's customization spec → datasource returned nothing
    Bug 2: 99-disable file had "disable" instead of "disabled" →
      cloud-init stayed active for networking

  The trap:
    Cloud-init ACTIVE ENOUGH to overwrite manual configs on every boot.
    Cloud-init BROKEN ENOUGH to not receive GUI configs (no tools).
    Every path blocked — GUI doesn't work, manual doesn't survive reboot.

  Fix: corrected the typo to "disabled" → cloud-init stopped managing
  network → manual config stuck. But FusionCompute GUI network editing
  remained dead for this VM because cloud-init (the delivery mechanism
  for GUI settings) was now disabled.

  Lesson: the hypervisor GUI doesn't SSH into the VM. It writes config
  to a datasource (ISO, metadata, customization spec) and relies on
  cloud-init inside the guest to apply it. Break cloud-init = break
  the bridge between hypervisor and guest.

---

Proxmox ide2 CD-ROM — why it stays attached:

  After VM is built, the cloud-init CD-ROM (ide2, media=cdrom) remains.
  Not a leftover — intentional. Cloud-init checks it every boot.
  If you change settings in Proxmox UI or Terraform, VM picks them up
  on next boot from the updated ISO.

  Safe to remove: cloud-init caches config in /var/lib/cloud/ after
  first run. But removing it means future Terraform IP/hostname changes
  won't reach the VM.

  Uses IDE (not SCSI) because every BIOS and OS can read IDE CD-ROM
  without special drivers. Actual disks use VirtIO SCSI for performance.

---

LXC containers — why no cloud-init:

  LXC shares the host kernel. Proxmox has direct access to the
  container's rootfs from the host side. No black box, no need for
  a messenger.

  Before the container starts, Proxmox:
    → writes /etc/hostname directly
    → writes /etc/NetworkManager/system-connections/eth0.nmconnection directly
    → injects SSH keys directly
    → sets DNS directly

  Same Terraform initialization block, completely different mechanism:
    VM:  Terraform → Proxmox → burns ISO → attaches CD-ROM → cloud-init reads it
    LXC: Terraform → Proxmox → writes directly into container filesystem → done

  That's why LXC has no ide2 CD-ROM attached. No datasource needed.
  The config is already planted before the container is alive.

  This is also why cloning LXC (TS-TF-003) didn't work like VMs.
  VMs clone + cloud-init customizes. LXC clone has no cloud-init to
  customize after clone. Solution: convert LXC to template (.tar.gz),
  Proxmox unpacks fresh rootfs and injects config during creation.

---

Delivery mechanism comparison — why FusionCompute breaks but Proxmox doesn't:

  Platform          Delivery mechanism              If agent/tool missing
  FusionCompute     open-vm-tools (software channel) Config never reaches VM
  Proxmox VMs       IDE CD-ROM (virtual disk)        Still works, no agent needed
  Proxmox LXC       Direct filesystem write           N/A, no agent involved
  AWS EC2           HTTP metadata (169.254.169.254)   Still works, no agent needed

  FusionCompute is the only one that depends on software inside the guest
  for delivery. The others use hardware (disk) or network (HTTP) that
  the guest can access natively.

---

Terraform cloud-init edit behavior:

  When you change IP in Terraform initialization block:
    1. terraform apply → API call to Proxmox
    2. Proxmox regenerates the ISO on ide2 with new config
    3. Nothing happens inside the running VM — still has old IP
    4. Proxmox GUI shows updated cloud-init settings (reads from ISO)
    5. Next reboot → cloud-init reads new ISO → applies new IP

  The ISO is updated immediately. The VM doesn't read it until reboot.
  Terraform may show "changed" but VM behavior doesn't change until restart.
