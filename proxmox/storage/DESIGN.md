# Storage layer — design notes and reasoning

Why the storage is split the way it is: OS disks on local Proxmox volumes, data / PVs / backups on the NAS. Reads as a narrative — for the concrete NAS config, NFS shares, firewall rules, and per-host storage setup, see [`nas-storage-config.md`](nas-storage-config.md).

---

## Why OS disks stay on local Proxmox storage, not on the NAS

The NAS is a FLASHSTOR unit with NVMe already installed (`ASUSTOR FS6706T`, 1.8 TB EXT4). Fast enough that my first instinct was: *put everything on the NAS — OS disks for every VM and LXC, VM images, PVs, backups, the lot. Central storage, easy to manage, one backup surface.*

I walked that back during the design phase. The OS-disk piece of that plan turned out to be a bad idea, and the reasoning applies beyond this specific project.

### Why I rejected NAS-backed OS disks

1. **OS disks need to be fast *and* independent of the network.** If the OS disk of a VM lives on NFS, then the VM's boot process, its `/var/log` writes, its systemd lifecycle — all of it is hostage to a healthy L2 path between the Proxmox host and the NAS. A switch flap, a bad cable, a NAS reboot, a NIC renegotiation — any of those turn into *VM-level* instability that looks like the VM is broken when actually the storage underneath it is. OS disks deserve the shortest, most reliable path possible. That path is the local NVMe in the Proxmox host itself.

2. **Kubernetes etcd needs stable, very fast storage.** The k8s masters in this setup run their etcd data directory on the VM's OS disk. Etcd is latency-sensitive and fsync-heavy — a 20ms hiccup on the disk surface is enough to trigger leader re-elections, which then cascade into API unavailability. Running etcd over NFS would be asking for cluster instability on every storage blip. Local NVMe gives etcd the deterministic fsync behaviour it needs.

3. **Clear failure isolation.** With OS disks local and data/PVs on NFS, I know exactly which failure mode I'm looking at when something breaks. A VM that won't boot? That's a local-disk / host problem. A pod that can't mount its PV? That's a NAS / storage-VLAN problem. Co-located storage would blur that line and make incident response slower.

4. **NAS is a single point of failure.** Good enough as a PV store where the app layer can retry or redeploy, not good enough as a boot surface for every host.

### Where the NAS earns its keep

Everything that *isn't* an OS disk:

| Use | Share | Client |
|-----|-------|--------|
| VM images / rootdirs for both envs | `prod-storage`, `dev-storage` | Proxmox hosts only |
| Shared ISO + CT template library | `shared-iso` | Both Proxmox hosts (RW) |
| k8s PersistentVolumes (prod pods) | `k8s-prod` | Prod k8s workers via CSI-NFS |
| k8s PersistentVolumes (dev pods) | `k8s-dev` | Dev k8s workers via CSI-NFS |
| vzdump VM backups | `Backups` | Both Proxmox hosts |
| SMB: Proxmox config backups | `Backups` (SMB) | Mac Mini admin only |

In short: **local disk for things that must boot fast and must never be blocked by the network; NAS for everything else.** OS + etcd on the local path, data + PVs + backups + templates on the NAS.

---

## Why k8s workers get a dedicated VLAN 40 NIC instead of proxying NFS through the Proxmox host

This came in later — it wasn't in the original Proxmox design but was added when CSI-NFS was introduced for pod PersistentVolumes.

The alternatives I could have picked:

- **Route pod NFS traffic through the Proxmox host's stor0 interface** — works, but every pod PV mount then passes twice through the hypervisor (once via vmbr1.40, once out to the NAS), and NFS latency stacks with virtualised-NIC latency.
- **Give each worker a VLAN 40 second NIC directly on vmbr1** — the worker talks to the NAS on its own VLAN 40 address, no hypervisor in the path for data traffic.

I picked the second approach because it matches the "each traffic plane gets its own NIC" pattern used on the Proxmox hosts themselves (see [`../DESIGN.md`](../DESIGN.md) → "Three traffic planes, physically separated"). The workers inherit the same separation — service traffic on VLAN 64 / 54 via vmbr0, storage traffic on VLAN 40 via vmbr1 — with no crossover.

This also means PV performance is no longer gated on how busy the hypervisor is. A hot etcd compaction on a master doesn't slow down a pod's NFS write on another node.

### IP range convention on VLAN 40

| Range | Purpose |
|-------|---------|
| `.100-.103` | Prod — Proxmox host + 3 k8s workers |
| `.110`      | Dev Proxmox host |
| `.120`      | NAS |
| `.201-.203` | Dev k8s workers |

Dev workers are in the `.200` range (not `.111-.113`) deliberately, to avoid any chance of accidental collision with Prod worker IPs — the NAS firewall allowlist on LAN 1 is the only thing between them, and a typo in an allowlist entry should never silently cross envs. Wide gaps make those errors impossible rather than merely unlikely.

---

## Related

- [`nas-storage-config.md`](nas-storage-config.md) — concrete NAS config: interfaces, firewall, NFS shares, Proxmox storage IDs, capacity allocation
- [`../../network/ip-planning.txt`](../../network/ip-planning.txt) — full VLAN 40 address plan
- [`../DESIGN.md`](../DESIGN.md) — Proxmox-layer design story (where the 3-plane NIC pattern is established)
