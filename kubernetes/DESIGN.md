# Kubernetes layer — design notes and reasoning

How this k8s layer evolved from "just deploy stuff" into what it is now. There wasn't a big upfront design — the cluster kept throwing surprises and I kept solving them, and the design emerged from that. Reads as a narrative, not a runbook.

Subfolder-specific design lives in its own `DESIGN.md` alongside the code:

- [`dev/flux/DESIGN.md`](dev/flux/DESIGN.md) — Flux architecture, the infrastructure→apps split, health checks, `flux diff` adoption, and the incidents that drove each decision
- [`dev/deployments/apps/remediation/DESIGN.md`](dev/deployments/apps/remediation/DESIGN.md) — self-healing system: why node-only checking, why 1 replica on master, why restore-at-same-VMID

---

## 1. Why 3 masters + 3 workers

There wasn't a deep pre-design here. I wanted 3+3 so I'd actually hit real HA scenarios — quorum loss, etcd member recovery, pod rescheduling under pressure, anti-affinity conflicts. A smaller cluster would've hidden those problems until they matter. The whole point was to learn as many failure modes as possible on dev before they surprise me on prod.

## 2. Iterative evolution, not planned architecture

The cluster design kept changing based on what broke:

- Started deploying manifests manually, moved to **Flux GitOps** after realizing manual applies don't scale and drift is invisible. Then Flux itself caused incidents (TS-K8S-019 cascade, TS-K8S-042 retry storm) that forced me to learn how it actually works underneath.

- **Vault agent injection** became a core dependency — every workload that needs secrets uses it. That created a hard ordering requirement: Vault injector must be healthy before any app starts. This wasn't planned, it emerged after pods kept crashlooping because the injector wasn't ready (TS-K8S-019).

- **Infrastructure→apps split** in Flux came from CRD race conditions (TS-K8S-012). Flux tried deploying HelmReleases before their CRDs existed. Splitting into two Kustomizations with `dependsOn` fixed it.

The cluster keeps revealing hidden surprises and I keep solving them with root cause analysis in the troubleshooting folder. Stability is genuinely getting better over time — each incident hardens something.

## 3. Self-healing remediation pod

I built a remediation system that watches worker node Ready status and auto-remediates through Proxmox API: reboot → reset → restore from latest backup. It runs on masters only (firewall — only master VLAN reaches Proxmox port 8006).

There are real risks in its approach:
- If a backup is running at the same time, remediation could conflict with vzdump
- If an IO storm hits and workers lose connection to masters, it could misidentify the problem

But most of these have been covered with cross-safety measures:
- The IO storm watchdog catches the actual source VM before remediation triggers on victims
- vzdump backups on k8s nodes were disabled entirely (see point 5)
- The 5-minute check interval + 2-minute verify window means it won't fire on transient issues

Full design reasoning is in [`dev/deployments/apps/remediation/DESIGN.md`](dev/deployments/apps/remediation/DESIGN.md).

## 4. IO storm — the 7-hour investigation

This was the hardest incident so far. The cluster kept getting overwhelmed by IO storms — all VMs would go unresponsive, VMs stuck at boot, the whole environment dead.

After 7-8 hours of continuous investigation, I found the root cause: a single VM generating massive etcd IO would saturate the shared NVMe, cascading IO pressure to every other VM on the same drive. The source VM showed high CPU + zero IO pressure (it was generating IO, not suffering from it), while victims showed moderate CPU + high IO pressure.

This led to three safety layers:
1. **IO throttle** (cgroup limits per VM) — contains the blast radius so one VM can't starve others
2. **IO storm watchdog** — daemon script that detects the source VM by its CPU+IO fingerprint and resets it automatically
3. **CPU stuck detection** — catches the case where the throttle works too well (source isolated but dead, watchdog can't see victims)

See: `troubleshooting/proxmox/` cases 17, 19, 20. Also `troubleshooting/kubernetes/` cases 38, 39, 42, 49, 50.

## 5. Why k8s nodes don't get automated backups

This was discovered during backup tuning (TS-PVE-020). I tested every combination — Snapshot/Suspend/Stop mode, NAS/local storage target, bandwidth limits from 50 to unlimited MiB/s. Every single one crashed the k8s cluster within seconds.

The root cause turned out to be data density. FreeIPA's disk is 91% zeros — vzdump skips them instantly, archive is 1.5 GB, zero IO impact. K8s node disks are full of real data (container images, overlay fs, etcd WAL, logs) that needs actual sustained reads from the shared NVMe.

**Solution:** excluded all k8s nodes from vzdump. They're cattle, not pets — Ansible rebuilds the VMs, kubeadm rejoins them, etcd-backup CronJob has the cluster state in S3, Flux resyncs all workloads from git. Manual backup only during quiet hours if I want a general copy.

FreeIPA and LXCs stay in the automated backup job — they run fine at full speed.

## 6. DR testing as a hardening loop

We run disaster recovery tests documented in the [`disaster-recovery/`](../disaster-recovery/) folder. Each test intentionally breaks something — kill a master, corrupt etcd, lose NFS — to verify recovery procedures and find gaps before they find us.

Every DR test has produced at least one surprise that improved the setup. The remediation pod, the IO throttle, the Flux health checks, the etcd-backup CronJob — all came from or were validated by DR testing. The cluster is more resilient today than it was a month ago, and next month it'll be better again.

That's the pattern: break it on purpose, learn, harden, repeat.

## 8. Dev drift — 2 workers instead of 3

Dev runs 2 workers (4GB each) while prod keeps the full 3+3. This is a deliberate resource optimization, not a feature gap.

The math: all the workloads that land on workers — Flux controllers, metrics-server, Helm operators, WordPress, MariaDB, Prometheus, Loki, Grafana, ingress-nginx, plus every DaemonSet (node-exporter, promtail, calico-node, kube-proxy, CSI-NFS) — can fit on 2 nodes. The question is whether they run better on 3×2.75GB or 2×4GB.

3 workers × 2.75GB = 8.25GB gross, but each node burns ~500MB on Linux kernel + kube-system DaemonSet pods before a single app runs. That's 1.5GB of overhead across 3 nodes, leaving ~6.75GB usable. With 2 workers × 4GB = 8GB gross, only 1GB overhead, leaving ~7GB usable. Fewer nodes, more headroom per node.

The secondary win: worker3's shutdown frees 2.75GB back to the Proxmox host. The dev server runs 13+ guests on a single NVMe with 24GB total — every megabyte returned to the hypervisor reduces the memory pressure that causes IO storms and OOM kills on the host level.

Worker3 still exists in Terraform (VM 1022) — it's just `started: false`, `on_boot: false`. The VM, its IPA enrollment, its kubelet cert on disk — all preserved. If I need it back, `terraform apply` with `started: true` brings it online and kubelet rejoins automatically. No rebuild required.

Remediation pod updated to monitor workers 1 and 2 only. Prod keeps all 3 workers in the remediation map.

This decision came directly from TS-K8S-051 — a cluster-wide rollout restart exposed that worker1 was already at 96% memory with OOM events. The rollout just made the underlying resource problem visible. See `troubleshooting/kubernetes/reference/51-worker1-rollout-restart-micro-cascade.md`.

---

## 7. etcd backup — automated snapshots, manual restore (for now)

A CronJob takes daily etcd snapshots and pushes them to S3. The upload uses a Vault-assumed IAM role, so no static AWS credentials sit in the cluster. That side is fully automated and working.

What I haven't built yet is an automated restore path — if I need a snapshot back, I pull it from S3 manually and feed it to `etcdctl snapshot restore`. The IAM policy attached to the Vault role already has `s3:GetObject` on the backup prefix, so the permissions are ready. It's just the tooling/procedure that needs building.

This is a deliberate priority call. The backup fires reliably, the snapshots are verified, and a manual restore takes maybe 10 minutes. Automating the restore is on the list but hasn't been worth the effort yet when there are bigger gaps to close first.
