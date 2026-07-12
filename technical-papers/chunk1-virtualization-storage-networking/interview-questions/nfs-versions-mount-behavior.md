NFS Versions and Mount Behavior
================================

Question:
  Compare NFSv3 and NFSv4. Why did you choose NFSv4 for Proxmox
  storage but NFSv3 for Kubernetes PVs? When would you choose one
  over the other? What is the difference between hard and soft mounts
  and what happens when storage becomes unreachable?

---

Answer Scenario:

NFSv3 vs NFSv4:
  NFSv3 is stateless — server doesn't track clients, each request
  is self-contained, server reboot is invisible to clients. But file
  locking needs a separate protocol (NLM) bolted on the side.

  NFSv4 is stateful — server tracks each client with a lease/session.
  Locking is built into the protocol. Tradeoff: if server reboots,
  there's a grace period (~90s) where clients must reclaim locks
  before new work starts.

Why NFSv4 on Proxmox:
  Proxmox writes VM disk images and backup archives to the NAS.
  Big files, long operations. Need the NAS to enforce locks so two
  hosts don't corrupt the same backup file. Statefulness protects you.
  Confirmed from: mount | grep nfs → vers=4.2 on all 3 NFS mounts.

Why NFSv3 on Kubernetes:
  K8s NFS CSI mounts are small reads/writes from pods — config files,
  uploads, shared data. Pods come and go constantly. Don't want the
  NFS server tracking sessions for pods that live 30 seconds.
  Stateless is simpler — pod reads, writes, dies, server doesn't care.
  No lease to expire, no grace period, no session cleanup.

When to choose which:
  - Multiple hosts writing same files, need locking → NFSv4
  - High pod churn, short-lived clients, simple IO → NFSv3
  - Server reboots need to be fast, no grace delay → NFSv3
  - Firewall simplicity (single port 2049) → NFSv4
    NFSv3 uses multiple ports including random RPC ports

SQLite corruption example (Grafana 3 replicas + 1 NFS PV):
  NFSv4 locking would NOT have saved this. SQLite uses POSIX file
  locks (fcntl) which don't work reliably across different NFS clients.
  SQLite's WAL uses shared memory (mmap) for coordination — mmap
  doesn't work across network filesystems. The architecture was wrong,
  not the NFS version. Fix: single replica or switch to MySQL/PostgreSQL.

---

Hard vs Soft mounts:
  hard (current config): retries forever, never returns error to app.
    Process blocks until NAS responds. Data integrity protected.
    timeo=600 (60s per retry), retrans=2.

  soft: gives up after retries, returns IO error to application.
    Faster failure, but VMs could get IO errors → disk corruption.

  Decision: kept hard because disk corruption is worse than a hang.

---

TS case reference: TS-PVE-009 (NFS shutdown hang during stor0 hot-swap)
  Adapter unplugged → NFS lost connectivity → reboot issued →
  systemd tries graceful unmount → hard mount retries forever at
  kernel level → shutdown hung for 3+ minutes.
  Fix: shutdown hook script that force-unmounts NFS before systemd
  reaches kernel-level unmount phase.

Open question from this TS case:
  UPS power failure scenario — NAS has no UPS, dies instantly.
  Server on UPS, UPS script triggers shutdown. The force-shutdown
  safety timer in the UPS script is a userspace process — it dies
  when systemd kills services, BEFORE the kernel-level NFS hang.
  Does the TS-9 hook cover this path? Never confirmed because the
  UPS scenario never hung. Could be the hook saved it, could be
  systemd's DefaultTimeoutStopSec forced through it. Unknown.
