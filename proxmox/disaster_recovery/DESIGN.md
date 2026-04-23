# Proxmox disaster recovery — design notes and scope

Why this folder exists next to the repo-level [`/disaster-recovery/`](../../disaster-recovery/), and why each subfolder belongs here and not there. Reads as a narrative — for the actual runbooks and scripts, see the subfolder READMEs.

---

## The boundary: host-layer runbooks vs platform-wide chaos tests

Two folders in this repo have "disaster recovery" in their names, and they are deliberately separate:

- [`/disaster-recovery/`](../../disaster-recovery/) — **platform-wide chaos test plans and results** across k8s / Vault / etcd / NFS / Nginx / IPA. Test-driven content. *"What I broke intentionally and what I learned."*
- `proxmox/disaster_recovery/` (this folder) — **Proxmox host-layer runbooks and prevention scripts**. Runbook-driven content. Procedures you follow when something real breaks at the hypervisor / hardware / electricity layer, plus live scripts protecting against host-specific environmental failures.

The `_` vs `-` is cosmetic; the scope difference is real. The repo-level folder is about *testing and discovery*. This folder is about *preventing or recovering from failures at the Proxmox / hardware / electricity layer* — the foundation everything else sits on.

## Why each subfolder belongs here

### `power/` — UPS / battery monitoring

Proxmox runs bare-metal on **laptops**. The built-in battery acts as an involuntary UPS. [`power/dr_ups_monitor.sh`](power/dr_ups_monitor.sh) samples battery state every 5 minutes and triggers a graceful shutdown if the host is discharging and capacity drops below a tiered set of thresholds. This isn't a chaos test — it's a live safeguard specific to the "Proxmox on a laptop" design choice documented in [`../DESIGN.md`](../DESIGN.md).

### `thermal/` — CPU temperature monitoring

Same reasoning as `power/`: laptops are not built for sustained server workload, and CPU temperature under k8s + VM load can creep toward throttling. [`thermal/draft-temperature_monitor.sh`](thermal/draft-temperature_monitor.sh) is the current draft — has known bugs documented in [`thermal/TODO.md`](thermal/TODO.md) (wrong sensor, no debounce, syntax errors). Needs a rewrite before deployment. Same "environmental safeguard for laptop-Proxmox" pattern as the UPS monitor.

### `hardware/` — physical component replacement runbook

[`hardware/usb-ethernet-adapter-replacement.md`](hardware/usb-ethernet-adapter-replacement.md) is the operational procedure for when a USB-Ethernet adapter fails — systemd `.link` files, MAC-to-interface mapping, safe replacement order (especially for the `stor0` adapter, where you need to unmount NFS first to avoid a shutdown hang). Triggered originally by a real incident (TS-NET-003); kept as a runbook because the same failure mode can recur on the cheap USB-ETH adapters the laptop-Proxmox design depends on.

### `recovery/` — full Proxmox host rebuild from backup

[`recovery/README.md`](recovery/README.md) is the "your Proxmox disk is dead" procedure: fresh install → run [`../bootstrap_proxmox/bootstrap.sh`](../bootstrap_proxmox/bootstrap.sh) + [`network-setup.sh`](../bootstrap_proxmox/network-setup.sh) → pull latest config tarball from NAS → apply → restore VMs/LXCs from vzdump → rotate API tokens. Ties directly to the config-backup + vzdump strategy in [`../backup/DESIGN.md`](../backup/DESIGN.md).

## What this folder deliberately does NOT contain

- **K8s / Vault / etcd / NFS / Nginx / IPA chaos tests.** Those are platform-layer and live in [`/disaster-recovery/`](../../disaster-recovery/).
- **Automated backup scripts.** Those live in [`../backup/`](../backup/). This folder *uses* those backups in `recovery/`, but doesn't own them.
- **Monitoring dashboards / alerting.** Anything Prometheus/Grafana-shaped is a k8s workload managed by Flux, not a host script.

The rule of thumb: if the failure mode is "the laptop ran out of battery", "the laptop got too hot", "a cable / adapter died", or "the Proxmox disk is gone and I need a fresh install" — it lives here. Everything above the hypervisor is platform-level and tested in `/disaster-recovery/`.
