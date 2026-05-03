# TS-LNX-006 | 2026-05-03 | OPEN | IMPROVEMENT
_____________________________________________________________________

[Info]
Domain: Linux / Storage / Partitioning
Sub-techs: LVM, golden image, cloud-init, Rocky Linux, /var, containerd, kubelet
Environment: dev + prod (all VMs built from golden image)
Re-opened: No

_____________________________________________________________________

[Issue Description]
Discovered during DR test: worker-disk-full-root-filesystem (2026-05-03).

/var is not a separate partition on any VM. The golden image (VMID 9001)
uses Rocky Linux default partitioning which puts everything under /.

Disk layout on k8s-worker3:
  ```
  /dev/mapper/rl-root   17G   13G  4.9G  72% /
  /dev/sdb2            960M  599M  362M  63% /boot
  ```

/var usage: 9.5 GiB of 13 GiB used (73% of all disk consumption).
Breakdown:
  /var/lib/containerd — container images, snapshots, layers
  /var/lib/kubelet — pod state, volumes, checkpoint data
  /var/log — system logs, journal, audit

Because /var isn't isolated, a runaway container image pull, log flood,
or container layer growth fills / and kills the entire OS — not just
container services. During the DR test, filling /var brought the whole
root filesystem to 100%, containerd died, kubelet crash-looped, node
went NotReady.

In production environments, /var is typically its own partition so
container/log growth can't take down the OS. The golden image needs
to be rebuilt with this separation.

_____________________________________________________________________

[Analysis]

# Evidence from DR test:

Pre-test:
  du -sh /var → 9.5G
  df -h /     → 17G total, 13G used, 4.9G available (72%)

/var is 73% of all disk usage. The remaining 3.5 GiB on / is the OS
itself (binaries, libraries, etc).

After filling /var to 100% and rebooting:
  - Node booted (/boot is separate — kernel + systemd load to memory)
  - OS was non-functional (can't write to /tmp, /var, anywhere)
  - containerd couldn't start → kubelet CRI failure → crash-loop
  - Node went NotReady

If /var had been a separate partition:
  - /var fills → containerd dies → kubelet crash-loops (same)
  - BUT / stays healthy → systemd works → SSH works → can clean up
  - OS-level recovery is possible without Proxmox console access

# Current golden image partitioning:

Rocky Linux 10.1 default installer creates:
  /boot     — 1 GiB (separate, ext4)
  /boot/efi — 600 MiB (EFI, if UEFI boot)
  swap      — ~2 GiB (LVM)
  /         — remainder (LVM, xfs)

No /var, no /tmp, no /home separation.

_____________________________________________________________________

[Potential Solutions]

Fix 1 — Rebuild golden image with /var as separate LVM logical volume:
  Suggested layout for 20 GiB disk:
    /boot     — 1 GiB
    /         — 8 GiB (OS only)
    /var      — 9 GiB (containers, logs, kubelet)
    swap      — 2 GiB

  Tradeoff: fixed partition sizes mean you can't dynamically share space.
  LVM makes it possible to resize later but not shrink xfs.

Fix 2 — Add /var alerting in Prometheus:
  Even without partition separation, can add granular monitoring:
    - Alert when `du /var` exceeds 80% of / total
    - Alert when /var/log growth rate spikes
    - Alert on container image count exceeding threshold

  This doesn't fix the isolation problem but gives earlier warning.

Fix 3 — Apply to existing VMs:
  Can't repartition live VMs without data loss. Options:
    a) Rebuild from new golden image (destroy + recreate)
    b) Add a second disk and mount as /var (migrate data)
    c) Accept risk on existing VMs, apply fix to new VMs only

  For k8s workers: option (a) is safest — drain node, recreate from
  new image, rejoin cluster. One node at a time.

_____________________________________________________________________

[Final Root Cause]
Golden image uses Rocky Linux default partitioning — no /var separation.
Container runtime (/var/lib/containerd), kubelet state (/var/lib/kubelet),
and system logs (/var/log) all compete for the same root filesystem space.
Growth in any of them can kill the OS.

_____________________________________________________________________

[Final Solution]
PENDING — golden image needs rebuild with /var as separate partition.
Existing VMs would need rolling replacement.

_____________________________________________________________________

[Risk Level] MEDIUM — any disk-heavy workload (image pull, log flood,
container layer leak) can silently fill / and bring down the node.
Currently mitigated by kubelet image GC but that's a one-shot defense.

_____________________________________________________________________

[References]
- Source: disaster-recovery/worker-disk-full-root-filesystem.md (DR test 2026-05-03)
- Related: TS-K8S-060 (monitoring gaps — absent metric alert for node-exporter)
- Related: TS-PVE-022 (Proxmox memory monitoring — related node health visibility)
- Golden image template: Proxmox VMID 9001
