Skill 12 — Virtualization / NAS (7 questions)
================================================

Format: Standard questions only. Project examples are ammunition.
Your Proxmox 2-laptop design, QEMU-mediated NFS, etcd on local NVMe,
VLAN 40 dedicated NIC for CSI-NFS, vzdump backup retention change,
IO throttle limits, golden template build, bare metal recovery — inject when earned.

---

1. What's the difference between Type 1 and Type 2 hypervisors?

   Coverage check:
   - Type 1 (bare metal): ESXi, Proxmox/KVM, Hyper-V — direct hardware access
   - Type 2 (hosted): VirtualBox, VMware Workstation — runs on top of OS
   - performance difference and why
   - KVM/QEMU architecture (KVM = kernel module, QEMU = userspace emulation)
   - virtio drivers — paravirtualization for better performance
   - resource overcommitment (CPU overcommit OK, memory overcommit risky)
   - balloon driver for memory reclaim
   - VM vs container — when to use each

2. How does live migration work?

   Coverage check:
   - moving a running VM from one host to another with minimal downtime
   - prerequisite: shared storage (both hosts access same disk)
   - pre-copy: iteratively copy memory pages, track dirty pages, converge
   - final switchover: pause source, copy last delta, resume on destination
   - stun time (last fraction of second)
   - post-copy: start on destination immediately, fetch pages on demand (faster but riskier)
   - cold migration: stop VM, copy everything (storage + memory), start on new host
   - analogy to K8s pod eviction (different mechanism, same availability goal)

3. What is the difference between a snapshot and a backup?

   Coverage check:
   - snapshot: point-in-time state, stored alongside original, fast to create
   - backup: independent copy, stored separately, survives source destruction
   - snapshot chains — why long chains degrade performance
   - snapshots are NOT backups (if disk dies, snapshots die too)
   - LVM snapshots, QEMU snapshots, ZFS snapshots
   - crash-consistent vs application-consistent snapshots
   - use cases: snapshot before risky change, backup for DR

4. How does NFS work and when would you use it?

   Coverage check:
   - network file system — file-level access over network
   - client-server model, mount remote export as local directory
   - NFSv3 vs NFSv4 (stateless vs stateful, port simplification, ACL support)
   - export options (/etc/exports): rw, ro, sync, root_squash, no_root_squash
   - hard mount vs soft mount — critical difference
     - hard: blocks until server responds (safe for databases)
     - soft: returns error after timeout (safe for apps that can retry)
   - NFS performance tuning (rsize, wsize, async)
   - when to use NFS vs iSCSI vs Ceph

5. How do you manage VM templates and golden images?

   Coverage check:
   - golden image: base OS + standard tools + security config
   - what belongs in template vs post-deploy config management (Ansible)
   - cloud-init for instance customization (hostname, SSH keys, network)
   - sealing a template (remove unique identifiers, SSH host keys, machine-id)
   - template storage and versioning
   - LXC templates vs VM templates (different mechanisms)

6. What is LVM and how does thin provisioning work?

   Coverage check:
   - PV (Physical Volume) → VG (Volume Group) → LV (Logical Volume)
   - extending volumes without downtime (lvextend + resize2fs/xfs_growfs)
   - thin provisioning: allocate more than physical capacity, grow on demand
   - overcommitment risks (what happens when thin pool fills)
   - monitoring actual vs allocated usage
   - LVM snapshots

7. Explain RAID levels — when would you use each?

   Coverage check:
   - RAID 0 (stripe — performance, no redundancy)
   - RAID 1 (mirror — redundancy, half capacity)
   - RAID 5 (stripe + parity — 1 disk fault tolerance, write penalty)
   - RAID 6 (double parity — 2 disk fault tolerance)
   - RAID 10 (mirror + stripe — performance + redundancy, 50% capacity)
   - rebuild time and risk (URE during rebuild on large RAID 5)
   - hot spares
   - hardware vs software RAID
