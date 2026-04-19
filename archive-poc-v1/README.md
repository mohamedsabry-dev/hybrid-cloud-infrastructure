# Archive — PoC v1 (VMware-based)

> **Status:** Archived. Not deployed. Not maintained. Kept as a portfolio
> record of the first iteration of this project and the incidents it
> generated. The current infrastructure (everything outside this folder) is a
> clean rebuild on completely different tech — Proxmox, MikroTik, Terraform,
> GitHub Actions, Flux-managed k8s. See `/deployment-docs/` and the top-level
> `network/`, `proxmox/`, `kubernetes/`, `aws/`, `ansible/`, `terraform/`
> folders for the current project.

---

## What this folder is

This was my first attempt at the hybrid cloud project. I built a VMware
vSphere homelab — nested ESXi inside VMware Workstation on a Windows host —
and ran it for about two months of active development. It was meant to
become the real thing: FreeIPA, Vault, Jenkins CI/CD, Veeam backup, and
eventually Kubernetes on top of it all.

I killed it before the Kubernetes phase. Everything in this folder is what
got built up to that decision point.

> **Design notes & retirement story** — for the 10 reasons I killed this PoC before the Kubernetes phase, and the mapping of every PoC-v1 piece to what the current stack replaced it with, see [`DESIGN.md`](DESIGN.md).

---

## What was in the PoC

| Category | Tech |
|----------|------|
| Hypervisor control plane | VMware vCenter 8 |
| Hypervisor | ESXi 8 (nested) |
| Host OS | Windows + VMware Workstation |
| Network | pfSense, nested VLANs, vMotion |
| Storage | NAS (iSCSI / NFS), ESXi datastores, RAID |
| Identity | FreeIPA, Kerberos, SSSD |
| Secrets | HashiCorp Vault (raft) |
| Backup | Veeam Backup & Replication (Community Edition, dual-instance) |
| CI/CD | Jenkins + Ansible |
| Monitoring | Prometheus + Grafana + Node Exporter |
| Scripting | PowerShell + Bash |

---

## Directory Structure (as archived)

```
archive-poc-v1/
├── README.md                   # This file
│
├── docs/                       # VMware-era documentation
│   ├── compute/                # VM specs, resource allocation
│   ├── failover/               # VM startup/shutdown order, DR procedures
│   ├── identity/               # FreeIPA, user accounts, IPA management
│   ├── network/                # pfSense config, VLANs, vMotion, NAS bonding (7 docs)
│   └── storage/                # NAS, datastores, snapshots, RAID (7 docs)
│
├── automation/
│   ├── ansible/
│   │   ├── cicd/               # Jenkins install playbook
│   │   ├── ipa/                # FreeIPA user/group/HBAC/sudo playbooks (+ legacy/)
│   │   ├── monitor/            # Node Exporter + Prometheus config
│   │   ├── os-services/        # Emergency user, Veeam backup planning
│   │   └── vault/              # Raft cluster install, policies, init guide
│   └── scripts/
│       ├── bash/               # Emergency user creation, pfSense commands, SSH cleanup
│       └── powershell/         # DR automation — battery monitor, emergency shutdown, Veeam kill scripts
│
└── troubleshooting/            # 31 real incidents from the PoC era
    ├── platform/               # 15 cases — vCenter, ESXi, FreeIPA, Windows host
    ├── storage/                # 10 cases — VMDK snapshots, NAS, corruption
    ├── network/                # 5 cases  — pfSense, network loops, routing
    └── application/            # 1 case   — Prometheus setup
```

---

## Why this is kept in the repo (not deleted)

1. **31 real troubleshooting cases with root-cause analysis.** Each one is a
   real incident I worked through — snapshot chain corruption, disk race
   condition on `/dev/sdX` vs UUID, Kerberos clock skew from VMware Tools
   time sync, Veeam application-aware backup triggering I/O errors,
   pfSense hardware-compat quirks, Windows host network loops, nested
   vSwitch promiscuous mode surprises. That material is portfolio-relevant
   even though the infra underneath it is retired.
2. **Hands-on-enterprise-tech evidence.** vCenter, ESXi, Veeam, pfSense,
   Jenkins, FreeIPA, HashiCorp Vault — real work on all of them, not just
   "I read about this".
3. **Decision trail.** This folder documents the *why* behind the current
   stack. Anyone reading the current project can see the version-1 attempt,
   the real pain points, and how the current design was shaped as a
   response.

---

## Troubleshooting — read this folder

The 31 incidents under [`troubleshooting/`](troubleshooting/) are the most portfolio-relevant thing in this archive. Each case has a full root-cause analysis written at the time, covering the kind of enterprise-tech surprises I hit with vCenter, ESXi, pfSense, Veeam, NAS, FreeIPA, and Windows hosting a nested lab. Good to skim — a lot of these issues show up in real production environments too, even though the underlying stack here is retired.

| Subfolder | Cases | Area |
|-----------|-------|------|
| [`troubleshooting/platform/`](troubleshooting/platform/) | 15 | vCenter, ESXi, FreeIPA, Windows host |
| [`troubleshooting/storage/`](troubleshooting/storage/) | 10 | VMDK snapshots, NAS, corruption |
| [`troubleshooting/network/`](troubleshooting/network/) | 5 | pfSense, loops, routing |
| [`troubleshooting/application/`](troubleshooting/application/) | 1 | Prometheus setup |

### If you only read five

These are the most interesting ones — the kind of incidents that teach you something you keep carrying into later projects:

- [`troubleshooting/storage/01-vmdk-snapshot-corruption.md`](troubleshooting/storage/01-vmdk-snapshot-corruption.md) — snapshot chain breakage from cross-partition vDisks
- [`troubleshooting/storage/03-disk-race-condition-disaster.md`](troubleshooting/storage/03-disk-race-condition-disaster.md) — `/dev/sdX` vs UUID mount, and what happens when reboot order reshuffles drive letters
- [`troubleshooting/platform/11-freeipa-time-sync-clock-skew.md`](troubleshooting/platform/11-freeipa-time-sync-clock-skew.md) — Kerberos failures traced to VMware Tools time-sync
- [`troubleshooting/network/05-duplicate-packets-loop.md`](troubleshooting/network/05-duplicate-packets-loop.md) — Windows IP forwarding creating duplicate packets on the host network
- [`troubleshooting/storage/09-application-aware-backup-loop-device-errors.md`](troubleshooting/storage/09-application-aware-backup-loop-device-errors.md) — Veeam AAP causing loop-device I/O errors

---

## Related

- **Current infrastructure docs:** [`/deployment-docs/`](../deployment-docs/)
- **Current troubleshooting (post-rebuild):** [`/troubleshooting/`](../troubleshooting/)
- **Current top-level structure:** [`/network/`](../network/), [`/proxmox/`](../proxmox/), [`/kubernetes/`](../kubernetes/), [`/ansible/`](../ansible/), [`/terraform/`](../terraform/), [`/aws/`](../aws/), [`/.github/workflows/`](../.github/workflows/)
