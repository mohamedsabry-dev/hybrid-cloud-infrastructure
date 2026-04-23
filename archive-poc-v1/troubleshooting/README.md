# Troubleshooting (PoC v1 — Archived)

> **Archived PoC v1 material.** These cases document real incidents hit during the
> VMware-based PoC that was retired before the Kubernetes phase. The infrastructure
> they refer to is no longer deployed. See [`../README.md`](../README.md) for the
> retirement story.
>
> Troubleshooting for the **current** project lives at
> [`/troubleshooting/`](../../troubleshooting/) (repo root).

**25 cases + 6 reference guides across 4 categories**

```
troubleshooting/
├── storage/                # 7 cases, 3 reference guides
├── platform/               # 13 cases, 2 reference guides
├── network/                # 4 cases, 1 reference guide
└── application/            # 1 case
```

Each subfolder has its own README with a case index. Reference guides live in `reference/` subfolders.

---

## Critical Incidents (7)

Cascading failures, data loss risk, or full-service outages.

| Ticket | Category | What Happened |
|--------|----------|---------------|
| [Storage-02](storage/02-nas-snapshot-sizing-failure.md) | Storage | 980GB thick disk, 450GB free — snapshot failed, NAS VM entered maintenance mode, cascading impact on all VM backups |
| [Storage-03](storage/03-disk-race-condition-disaster.md) | Storage | /dev/sdX names swapped on reboot — ALL VMs inaccessible, entire environment down |
| [Storage-05](storage/05-nas-memory-starvation.md) | Storage | NAS RAM reduced 5→4GB while doubling VMs — kernel soft lockups, 31-47s CPU stalls, NFS cache starvation |
| [Storage-07](storage/07-vmware-snapshot-chain-corruption.md) | Storage | Parent-child VMDK links broken from cross-drive snapshots — vdiskmanager + ESXi resignature recovery |
| [Storage-10](storage/10-snapshot-chain-corruption-sleep-mode.md) | Storage | Laptop slept mid-Veeam backup — thin disk inflated 98GB → 1TB, snapshot metadata destroyed |
| [Platform-08](platform/08-windows-host-sleep-network-break.md) | Platform | ESXi uplink down after laptop sleep/wake — all VMs lose network, vCenter unresponsive |
| [Platform-11](platform/11-freeipa-time-sync-clock-skew.md) | Platform | VMware Tools time sync fighting chrony — cascading Kerberos auth failures across all services |

---

## Storage — 7 cases

[reference/](storage/reference/) has 3 guides

| # | File | What Happened |
|---|------|---------------|
| 01 | [vmdk-snapshot-corruption](storage/01-vmdk-snapshot-corruption.md) | Snapshots on different partitions = broken chain |
| 02 | [nas-snapshot-sizing](storage/02-nas-snapshot-sizing-failure.md) | 980GB disk, 450GB free — snapshot failed, VM entered maintenance mode |
| 03 | [disk-race-condition](storage/03-disk-race-condition-disaster.md) | /dev/sdX names swapped on reboot — ALL VMs inaccessible |
| 05 | [nas-memory-starvation](storage/05-nas-memory-starvation.md) | NAS RAM cut while doubling VMs — kernel soft lockups, 31-47s CPU stalls |
| 07 | [snapshot-chain-corruption](storage/07-vmware-snapshot-chain-corruption.md) | Parent-child VMDK links broken from cross-drive snapshots |
| 09 | [veeam-aap-loop-device](storage/09-application-aware-backup-loop-device-errors.md) | Loop device I/O errors during Veeam AAP — hidden resource costs |
| 10 | [snapshot-corruption-sleep](storage/10-snapshot-chain-corruption-sleep-mode.md) | Laptop slept mid-Veeam backup — thin disk inflated 98GB → 1TB |

---

## Platform — 13 cases

[reference/](platform/reference/) has 2 guides

| # | File | What Happened |
|---|------|---------------|
| 01 | [vcenter-install-hang](platform/01-vcenter-installation-stage2-hang.md) | vCenter installation stuck Stage 2 — DNS resolution failure |
| 02 | [vcenter-sso](platform/02-vcenter-authentication-error-sso.md) | SSO authentication failing — alias whitelist |
| 03 | [lifecycle-manager-depot](platform/03-vcenter-lifecycle-manager-depot-error.md) | Deprecated update repository URLs |
| 05 | [cert-manager](platform/05-vcenter-certificate-manager-replace-failed.md) | Certificate replacement failed — service health issues |
| 06 | [api-ssl](platform/06-vcenter-api-ssl-error-after-root-ca.md) | API SSL verification fails — trust store out of sync with new CA |
| 08 | [windows-sleep-network](platform/08-windows-host-sleep-network-break.md) | ESXi uplink down after laptop sleep/wake — all VMs lose network |
| 10 | [vapp-config](platform/10-vcenter8-vapp-config-not-persisting.md) | vApp config resets on restart — database transaction bug |
| 11 | [freeipa-clock-skew](platform/11-freeipa-time-sync-clock-skew.md) | VMware Tools time sync fighting chrony — cascading Kerberos auth failures |
| 12 | [sssd-cache](platform/12-freeipa-sssd-cache-not-updating.md) | Sudo rule changes not reflecting in SSSD cache |
| 13 | [vcenter-backup-ip-change](platform/13-vcenter-backup-failure-after-ip-change.md) | Backup fails after IP/hostname change — chain metadata references old values |
| 14 | [lifecycle-plugin](platform/14-vsphere-lifecycle-manager-plugin-download-error.md) | Plugin download fails after IP/certificate change |
| 15 | [firewall-interface](platform/15-vcenter-firewall-invalid-interface-error.md) | Firewall GUI fails on deleted NIC references |
| 16 | [esxi-autoprotect](platform/16-esxi-master-autoprotect-snapshot-performance-degradation.md) | 12 accumulated snapshots — 6min of 1-8s disk latency |

---

## Network — 4 cases

[reference/](network/reference/) has 1 guide

| # | File | What Happened |
|---|------|---------------|
| 04 | [promiscuous-mode](network/04-promiscuous-mode-nested.md) | Nested VMs isolated — promiscuous mode not enabled on vSwitch |
| 05 | [duplicate-packets](network/05-duplicate-packets-loop.md) | 3x duplicated pings — promiscuous mode + redundant uplinks |
| 07 | [windows-host-loops](network/07-windows-host-network-loops.md) | Packet duplication and ARP corruption from Windows IP forwarding |
| 08 | [static-route-loop](network/08-static-route-loop-ssh-disconnect.md) | SSH hangs — duplicate static routes creating routing loop |

---

## Application — 1 case

| # | File | What Happened |
|---|------|---------------|
| 01 | [prometheus-setup](application/01-prometheus-setup-issues.md) | Port conflict and YAML parsing errors during deployment |

---

## Incident Patterns

The storage incidents tell a progression — the same class of problem (snapshot management on constrained hardware) hit repeatedly, each time deeper:

```
Storage-01 (snapshot corruption)
    → Storage-03 (disk race condition — full outage)
        → Storage-07 (snapshot chain — major recovery)
            → Storage-10 (sleep-mode corruption — catastrophic)
```

Each failure led to architectural hardening that carried forward into the current Proxmox iteration.
