# PoC v1 — design notes and retirement story

Why the VMware-based PoC was built, what was in it, why I killed it before the Kubernetes phase, and what the current stack replaced each piece with. Reads as a narrative — for the folder status, contents, and troubleshooting index see [`README.md`](README.md).

---

## Why I killed it (and started over with a different stack)

This was supposed to become the real project. I was planning to build Kubernetes on top of it once Vault was stable. After two months of building it, though, the cracks added up faster than the progress, and when I stepped back and looked at the list honestly I realised shipping k8s on top of this foundation would just bake in the problems deeper. So I shut it down after the Vault cluster was stable — right before the Kubernetes phase — and restarted with a completely different stack.

The combined reasons, in the order they actually hit me:

1. **Nothing was reproducible.** Everything was manual setup in vCenter and Workstation GUIs. Rebuilding the environment meant re-clicking for hours. For a project meant to demonstrate "infrastructure as code", the base was anything but.
2. **vCenter bugs across many areas.** SSO, installation stages, certificate lifecycle, backup after IP change, firewall interface errors. See `troubleshooting/platform/` (cases 01-16) — each one ate real time.
3. **Windows host + VMware Workstation + Windows Update = storm of instability.** Forced Windows reboots at the worst times, Workstation interacting badly with Windows updates, whole nested lab going down unexpectedly.
4. **Windows ate RAM.** The host OS was fighting the lab for memory. I couldn't freely deploy what I wanted because Windows itself took too much of the budget.
5. **Everything was virtualised — no physical hands-on.** Network, storage, all of it sat inside VMware Workstation's virtual networking. No real cables, no real switch, no real router. For a project that is supposed to be a *hybrid cloud* story, having zero hands on real hardware wasn't acceptable to me.
6. **Jenkins felt old.** For a portfolio piece in 2026 I want GitHub Actions + OIDC + GitOps, not a Jenkins shop.
7. **Veeam Community Edition.** Hard cap at 10 nodes for backup. I kept hitting it and working around it.
8. **VMware Workstation NAT was a debugging hole.** Tracing or sniffing traffic through Workstation's NAT layer was practically impossible. Every network issue became guesswork.
9. **vCenter consumed enormous amounts of RAM** — the control plane itself was a major workload on the host.
10. **ESXi memory ballooning** caused intermittent workload instability.

No single item was fatal. The combination was. I stopped, replanned the stack from scratch, and started the current version of the project.

---

## What the current stack replaced each piece with

| PoC v1 (retired) | Current stack (elsewhere in this repo) |
|-------------------|----------------------------------------|
| VMware Workstation + vCenter + ESXi | **Proxmox VE** on bare-metal laptops (`/proxmox/`) |
| pfSense | First ER605, now **MikroTik L009UiGS-RM** (`/network/router/mikrotik/`) |
| Jenkins | **GitHub Actions** with self-hosted runners + OIDC auth to AWS (`/.github/workflows/`) |
| Manual GUI setup | **Terraform + Ansible** IaC (`/terraform/`, `/ansible/`) |
| Veeam Community | Native Proxmox VM backups + k8s-layer backups (etcd cronjob, PV snapshots) |
| Virtualised-only networking | Real physical switch (Festa FS308GP), AP (AC750), cabling, VLAN trunks |

## What stayed (philosophically)

- **FreeIPA** for identity + DNS (rebuilt from scratch on the new stack)
- **HashiCorp Vault** for secrets (rebuilt — now with AWS KMS auto-unseal)
- **Prometheus / Grafana** for monitoring (rebuilt as k8s workloads via Flux)
- **Two-environment dev/prod split** (rebuilt cleaner on the new stack)

The ideas survived. The implementation didn't.
