# Troubleshooting (PoC v1 — Archived)

> **Archived PoC v1 material.** These cases document real incidents hit during the
> VMware-based PoC that was retired before the Kubernetes phase. The infrastructure
> they refer to is no longer deployed. See [`../README.md`](../README.md) for the
> retirement story.
>
> Troubleshooting for the **current** project lives at
> [`/troubleshooting/`](../../troubleshooting/) (repo root).

**Total: 23 issues + 8 reference guides across 4 categories**

---

## Critical Incidents

Issues with system-wide blast radius, cascading failures, or data integrity risk.

| Ticket | Category | What Happened | Blast Radius |
|--------|----------|---------------|-------------|
| [Storage-03](storage/03-disk-race-condition-disaster.md) | Storage | /dev/sdX names swapped on reboot — ALL VMs inaccessible, entire environment down | Full infrastructure |
| [Storage-05](storage/05-nas-memory-starvation.md) | Storage | NAS RAM reduced 5→4GB while doubling VMs — kernel soft lockups, 31-47s CPU stalls, NFS cache starvation | Full infrastructure |
| [Storage-07](storage/07-vmware-snapshot-chain-corruption.md) | Storage | Parent-child VMDK links broken from cross-drive snapshots — vdiskmanager + ESXi resignature recovery | Data integrity |
| [Storage-10](storage/10-snapshot-chain-corruption-sleep-mode.md) | Storage | Laptop slept mid-Veeam backup — thin disk inflated 98GB → 1TB, snapshot metadata destroyed | Data integrity + storage |
| [Platform-08](platform/08-windows-host-sleep-network-break.md) | Platform | ESXi uplink down after laptop sleep/wake — all VMs lose network, vCenter unresponsive | Full infrastructure |
| [Platform-11](platform/11-freeipa-time-sync-clock-skew.md) | Platform | VMware Tools time sync fighting chrony — cascading Kerberos auth failures across all services | Full authentication |

---

## Cases by Category

### Storage — 7 issues ([reference/](storage/reference/) has 3 guides)

**High:**

| # | File | What Happened |
|---|------|---------------|
| 01 | [01-vmdk-snapshot-corruption](storage/01-vmdk-snapshot-corruption.md) | Snapshots on different partitions = broken chain |
| 02 | [02-nas-snapshot-sizing](storage/02-nas-snapshot-sizing-failure.md) | 980GB disk, 450GB free — snapshot failed, VM entered maintenance mode |
| 09 | [09-veeam-aap-loop-device](storage/09-application-aware-backup-loop-device-errors.md) | Loop device I/O errors during Veeam AAP — hidden resource costs |

---

### Platform — 13 issues ([reference/](platform/reference/) has 2 guides)

**High:**

| # | File | What Happened |
|---|------|---------------|
| 01 | [01-vcenter-install-hang](platform/01-vcenter-installation-stage2-hang.md) | vCenter installation stuck Stage 2 — DNS resolution failure |
| 16 | [16-esxi-autoprotect](platform/16-esxi-master-autoprotect-snapshot-performance-degradation.md) | 12 accumulated snapshots — 6min of 1-8s disk latency, VMXNET3 driver errors |
| 13 | [13-vcenter-backup-ip-change](platform/13-vcenter-backup-failure-after-ip-change.md) | Backup fails after IP/hostname change — chain metadata references old values |

**Medium:**

| # | File | What Happened |
|---|------|---------------|
| 02 | [02-vcenter-sso](platform/02-vcenter-authentication-error-sso.md) | SSO authentication failing — alias whitelist |
| 03 | [03-lifecycle-manager](platform/03-vcenter-lifecycle-manager-depot-error.md) | Deprecated update repository URLs |
| 05 | [05-cert-manager](platform/05-vcenter-certificate-manager-replace-failed.md) | Certificate replacement failed — service health issues |
| 06 | [06-api-ssl](platform/06-vcenter-api-ssl-error-after-root-ca.md) | API SSL verification fails — trust store out of sync with new CA |
| 10 | [10-vapp-config](platform/10-vcenter8-vapp-config-not-persisting.md) | vApp config resets on restart — database transaction bug |
| 12 | [12-sssd-cache](platform/12-freeipa-sssd-cache-not-updating.md) | Sudo rule changes not reflecting in SSSD cache |
| 14 | [14-lifecycle-plugin](platform/14-vsphere-lifecycle-manager-plugin-download-error.md) | Plugin download fails after IP/certificate change |
| 15 | [15-firewall-interface](platform/15-vcenter-firewall-invalid-interface-error.md) | Firewall GUI fails on deleted NIC references |

---

### Network — 4 issues ([reference/](network/reference/) has 1 guide)

**Medium:**

| # | File | What Happened |
|---|------|---------------|
| 04 | [04-promiscuous-mode](network/04-promiscuous-mode-nested.md) | Nested VMs isolated — promiscuous mode not enabled |
| 05 | [05-duplicate-packets](network/05-duplicate-packets-loop.md) | 3x duplicated pings — promiscuous mode + redundant uplinks |
| 07 | [07-ip-forwarding-loops](network/07-windows-host-network-loops.md) | Packet duplication and ARP corruption from Windows IP forwarding |
| 08 | [08-static-route-loop](network/08-static-route-loop-ssh-disconnect.md) | SSH hangs from routing loop — duplicate static routes |

---

### Application — 1 issue

**Medium:**

| # | File | What Happened |
|---|------|---------------|
| 01 | [01-prometheus-setup](application/01-prometheus-setup-issues.md) | Port conflict and YAML parsing errors during deployment |

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
