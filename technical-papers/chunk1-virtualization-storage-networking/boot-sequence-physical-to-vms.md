Boot Sequence Part 1 — Physical Host to Running VMs and LXCs (Summary Trace)
==============================================================================

pre-trace (one-time bootstrap):
  Proxmox bare-metal on laptop, bootstrap.sh (NTP, repos, users), network-setup.sh (WiFi, bridges, VLANs)
    → golden templates: VM (9001, Rocky + guest-agent + cloud-init) and LXC (9010)
    → all VMs/LXCs cloned via Terraform with startup order + delays configured

power button → UEFI → GRUB → Proxmox kernel
  → systemd: networking (bridges up) → WiFi (wpa_supplicant) → NFS client (mounts attempt)
    → pvedaemon + pveproxy + pvestatd + pvescheduler
      → @reboot cron: io-storm-watchdog (dev), temperature_monitor (prod)

→ autostart sequence reads startup.order from each VM/LXC config
  → startup_delay delays the NEXT VM, not current (TS-PVE-012)

→ order 1: Ansible LXC (2001) boots on local-lvm (no NFS needed)
  → 300s delay — NAS initializes, NFS hard mounts unblock (were hanging until NAS responded)

→ order 2: FreeIPA VM (1001) boots → cloud-init (IP, hostname, SSH keys)
  → named (DNS for lab.local) + krb5kdc (Kerberos) + ipa (LDAP) start
    → 60s delay for DNS to stabilize

→ order 3: Runner LXC (2003): GitHub Actions self-hosted runner
→ order 4: NGINX LXC (2002): reverse proxy (legacy, replaced by ingress-nginx in K8s)

→ order 5-7: Vault cluster LXCs (2004, 2005, 2006) boot sequentially (60s gaps)
  → vault server starts → detects sealed → AWS KMS auto-unseal
    → Raft leader election after 2/3 quorum → ~4 min to stable cluster

→ order 8: K8s masters x3 (1010-1012) boot in parallel
  → containerd → kubelet → etcd → kube-apiserver → scheduler → controller-manager
    → master3 has 180s delay before workers can start

→ order 9: K8s workers x3 (1020-1022) boot in parallel
  → containerd → kubelet → registers with API server → NotReady (no CNI yet)

→ test VMs (1030-1031): on_boot=false, manual start only

total: ~17 min from power button to all VMs/LXCs running
  → continues in boot-sequence-k8s-to-operational.md
