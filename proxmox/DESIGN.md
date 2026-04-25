# Proxmox layer — design notes and reasoning

How this Proxmox layer actually came to be — iteration history and layer-level decisions. Reads as a narrative, not a runbook — for the practical setup steps see [`README.md`](README.md).

Subfolder-specific stories live in their own `DESIGN.md` alongside the code:

- [`bootstrap_proxmox/DESIGN.md`](bootstrap_proxmox/DESIGN.md) — how the Proxmox host bootstrap scripts grew, why they're split, why Terraform gets its own Proxmox user
- [`golden_templates/DESIGN.md`](golden_templates/DESIGN.md) — what goes in a golden template vs Ansible, the debug-tools philosophy, the fix-then-backport loop

---

## Proxmox 8 → 9 within a day

I started on Proxmox **8.x** because I assumed older would mean more stable docs and more community answers to whatever I hit.

One day in, I read up on what 9.x actually brought for my use case: LXC improvements, features I wanted, genuine stability upgrades, and better Terraform-provider maintainability on the `bpg/proxmox` side. I reinstalled on **9.x** the same week. The "older is more stable" heuristic didn't survive five minutes of the 9.x changelog.

## From "one laptop, fully nested" to two physical hosts

When I started scoping this I was still carrying PoC-era thinking: **one laptop, two nested Proxmox instances, virtualised everything** — virtual network, virtual storage (TrueNAS VM), virtual router (pfSense VM). The pitch I gave myself was the RAM math versus the retired VMware stack:

- ~8 GB freed (no Windows host)
- ~8 GB freed (no vCenter)
- ~5 GB freed (no Veeam)
- **≈ 20 GB freed for actual workloads**

Plan was: direct ethernet from that laptop to the home router, done.

Two things made me walk away from that plan during the design phase:

1. **I wanted this project to be a "stadium"** — a long-lived learning space that could absorb new tech entering the field over years, not just fit this moment's stack. Fully-nested virtualization on one machine stops being a stadium the moment you hit any hardware-level question.
2. **I wanted real physical hands-on.** Same motivation that killed the VMware PoC (see [`../archive-poc-v1/README.md`](../archive-poc-v1/README.md)). No more virtual networks hiding real behaviour.

This happened in parallel with the AWS decision (1 account vs 2 accounts — see [`../aws/bootstrap.md`](../aws/bootstrap.md)). Both landed on "proper separation, accept the duplication cost".

## The decisions that physicalised the stack

Once "real hardware, stability, long-term" became the goal, each design piece moved off VMs onto hardware:

| Role | First plan | Landed on |
|------|------------|-----------|
| Storage | TrueNAS VM | Dedicated NAS (ASUSTOR FS6706T) |
| Second hypervisor | Nested Proxmox on same laptop | Second physical laptop for dev |
| Router / firewall / VPN | pfSense VM | Physical router (first ER605, now MikroTik — see [`../network/README.md`](../network/README.md)) |
| NFS server | Linux/TrueNAS VM | On the NAS hardware directly |

The small dev laptop's resource constraints reinforced all of this — it couldn't fit router + storage + compute simultaneously as VMs, which made the "run hardware for non-compute roles" pattern feel natural instead of forced.

## Dev as a smaller mirror of prod

Dev runs on an older, smaller laptop; prod runs on the newer/bigger one. Dev is a **complete mirror of prod at smaller scale** — same topology, same tools, same tool versions, smaller resource allocations. This is the enterprise pattern I've seen in real jobs: every change lands on dev first, only after it works does it move to prod. Any Terraform resource-tier differences you see between the two envs (`k8s_masters` memory, worker RAM, Vault memory, etc.) are deliberate tier sizing, not drift to mirror.

## Three traffic planes, physically separated

Part of "I want to actually learn networking" was deciding that each traffic plane should have its own NIC, not just its own VLAN on a shared NIC. So for each Proxmox laptop I added:

- **2× USB-Ethernet adapters** (one Type-A, one Type-C) — one carries the service VLAN trunk (`svc0`, VLANs 50-55 / 60-65), the other carries the storage VLAN 40 trunk (`stor0`).
- **Built-in WiFi** — used as the management plane, joining the lab's `unified_mgmt` SSID served by the AC750 AP.

Three physically separate planes per host: WiFi = management, USB-ETH-A = service, USB-ETH-C = storage. Management-over-WiFi is unusual; it's a consequence of the laptop form factor (no second built-in wired port). It works fine in practice — mgmt traffic is light, and the AP enforces client isolation anyway.

## Subfolder stories

Each subfolder under `proxmox/` owns its own narrative in a local `DESIGN.md`:

- [`bootstrap_proxmox/DESIGN.md`](bootstrap_proxmox/DESIGN.md) — origin of the manual-first bootstrap scripts, why they're split (SSH-disconnect risk on `network-setup.sh`), the Terraform Proxmox user model, and what the scripts deliberately don't do.
- [`golden_templates/DESIGN.md`](golden_templates/DESIGN.md) — how the golden VM/LXC package list grew, the "ship debug tools before you need them" philosophy, what belongs in golden vs Ansible, and the Rocky 9→10 filename legacy.
- [`storage/DESIGN.md`](storage/DESIGN.md) — why OS disks stay on local Proxmox storage (not on the NAS), why k8s workers get a dedicated VLAN 40 NIC, and the IP-range convention that keeps dev/prod from colliding.
- [`backup/DESIGN.md`](backup/DESIGN.md) — why I'm NOT running Proxmox Backup Server, the config-backup + vzdump split, the disaster-recovery path it replaces PBS with, and the frequency / retention evolution.
- [`disaster_recovery/DESIGN.md`](disaster_recovery/DESIGN.md) — scope boundary between this folder (host-layer runbooks + prevention scripts) and the repo-level [`/disaster-recovery/`](../disaster-recovery/) (platform-wide chaos tests).
