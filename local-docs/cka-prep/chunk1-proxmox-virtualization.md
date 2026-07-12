# Interview Questions & Answers
Extracted from chunk reviews. My voice, my tone.

---

## Chunk 1: Proxmox + Bootstrap

### Q1: Tell me about your Proxmox bare-metal environment.

I got 2 laptops, installed Proxmox on both of them aimed to act like dev and production environments, plus a dedicated NAS for shared storage isolated on its own VLAN. Isolated the network traffic with 3 separated paths — management, service, and storage. Automated the server-side config process with a bootstrap bash script, infrastructure workload VMs with Terraform and the BPG provider, golden image templates with Terraform and bootstrap bash, and ongoing config with Ansible.

> Scope discipline: don't mention network, storage details, or any scope expansion unless they ask a separate question. Each new question = fresh 60-90 seconds.

### Q2: Why did you choose Proxmox over VMware?

I actually started with VMware. The first iteration ran on VMware Workstation inside Windows. Hit real limits — virtual switches weren't detected properly inside nested VMs, memory ballooning didn't release RAM immediately when a standby host migrated workloads, and vCenter alone needs ~14 GB RAM. I tried to cut it down to 7 GB by disabling unused services but it was constant workarounds to keep it alive. Proxmox runs with ~2 GB overhead, has built-in backup for workloads — no need to spend RAM on a separate Veeam instance which was community edition limited to 10 VMs per backup job anyway. I also initially considered that Proxmox can create its own virtual interfaces unlike VMware which sticks to available physical ones, but that argument became irrelevant when I decided to use physical USB-Ethernet adapters and WiFi for traffic separation. Before shutting down the VMware PoC I verified Terraform works with vSphere too, so tooling compatibility wasn't a comparison point — it was the resource overhead and architectural limits that drove the decision.

> Key signal: this isn't a fanboy answer. I ran VMware, hit real limits with 25 documented cases, then made a justified engineering decision to switch. The PoC wasn't wasted — it informed the redesign.

### Q3: Why do you have bootstrap scripts for Proxmox and what do they do?

After deploying Proxmox for the first time, I noticed some prompts related to the community version package repo, and some basic config needed — NTP, preparing the management user API token, WiFi-related packages, and so on. So I did every step manually first, recorded the commands, then decided to turn them into a bash script with sections for each step. Since bootstrap.sh needs some service restarts and it's better to do a full reboot after it, I isolated the network config into a separate script. At the beginning the host lives on the legacy network config over the service port for management, but that changes after the network setup script runs — it moves management to WiFi and frees the physical ports for service and storage traffic.

> Key signal: manual-first approach. Didn't start with automation — did it by hand, understood it, then scripted it. Shows the script is built from real understanding, not copied from a tutorial.

### Q4: What's the difference between LXC and VMs, and why did you use LXC for some workloads like Vault and Ansible?

LXC containers share the host kernel directly — very lightweight, faster to start, much lower RAM overhead. VMs have full kernel isolation with their own OS. The tradeoff is isolation: VMs are more secure because a kernel exploit in the guest can't reach the host, while in LXC the container processes are visible from the management host depending on privilege level — that's a weaker boundary.

I used LXC mainly because of RAM constraints. On the dev server I have 24 GB and needed to fit the same architecture as prod — 3 masters, 3 workers, FreeIPA, 3 Vault nodes, Ansible, NGINX, GitHub runner. Based on my capacity planning, putting Vault and the utility workloads in LXC saved enough RAM to make it work without drifting the architecture from prod. It also added a learning dimension — I got to understand LXC behavior, like how NTP works differently because the container shares the host kernel clock, or how FreeIPA client enrollment needs specific config adjustments for LXC.

But honestly, in a real production environment I'd lean toward VMs for anything security-sensitive like Vault. The isolation is stronger and more stable. LXC was the right call for a resource-constrained lab, not necessarily for production.

> Key signal: honest tradeoff reasoning. Not "LXC is better" — it's "LXC was the right choice given my constraints, and I know where it falls short." The NTP and FreeIPA examples show real operational experience with LXC quirks, not just theory.
>
> Nuance if pushed deeper: both LXC and VMs have their disks on the host's LVM/ZFS — the hypervisor admin can mount and inspect either. The real difference is runtime: LXC processes are visible via `ps` on the host (shared kernel), VM processes are hidden inside the guest kernel. But for disk access, both are transparent to whoever controls the hypervisor. The real security boundary is who has access to the hypervisor itself — that's why management is on its own isolated network plane.

### Q5: Tell me about your storage design.

I have one physical NAS connected to the switch on VLAN 40 tagged, and both Proxmox servers connect to the same VLAN on separate ports — so the storage traffic stays at L2 level, never touches the router. On the NAS side I configured interface-level security to accept only the 2 server IPs, and each server has access only to its specific share folder for environment isolation.

Later when I deployed Kubernetes, workers needed access to storage too — for the NFS CSI driver, so pods can use PersistentVolumes on the NAS instead of local disk. I originally planned local disks per VM, but realized during deployment that if a pod gets evicted to another node, its data would be stuck on the hardware attached to the original node. So I changed the design — added a storage bridge interface on the same VLAN 40 subnet to all workers on both dev and prod, and configured specific NAS folders per environment accepting only the IP list of that environment's workers.

NAS management itself goes over the WiFi port connected to the AP on the management plane, carried to the router over VLAN 5 untagged — separate from the data path.

> Gaps to revisit:
> - **stor0 bridge config**: don't remember the exact config method for the bridge adapter on Proxmox side. Review during Proxmox code read.
> - **NFS CSI driver details**: revisit during Chunk 7 (Kubernetes). Know the why, fuzzy on the exact component name and config.
> - **NAS share ACL config**: review the actual NAS-side access control setup in proxmox/storage/.
>
> Key signal: L2 isolation for storage traffic (no routing), per-environment folder ACLs, design change driven by real limitation discovered during deployment (not upfront theory).
>
> Follow-up if asked about data protection: "NAS runs RAID 1 across 2x2TB drives for redundancy, plus Proxmox backup jobs for workload-level protection."

---

## General Virtualization (not project-specific)

### Q6: What's the difference between Type 1 and Type 2 hypervisors?

Type 1 runs directly on hardware — Proxmox/KVM, ESXi, Hyper-V. Type 2 runs on top of an OS — VMware Workstation, VirtualBox. I've used both: Proxmox (Type 1) in the current project, VMware Workstation (Type 2) in the first PoC iteration.

**My first spoken attempt (May 10):** Got it right. Type 1 = hypervisor directly on hardware, direct access to CPU and memory. Type 2 = hypervisor on top of a host OS, resources go through an extra layer. Also anticipated the container follow-up — Docker host shares kernel, no hypervisor layer, lighter but less isolation. Connected to real IVS3800 environment where application runs in containers on a physical server's Docker host. Correct and complete.

### Q7: What's the difference between a VM and a container?

VM has its own full OS and kernel, hardware-level isolation via the hypervisor. Container shares the host kernel, process-level isolation, much lighter. I run both — VMs on Proxmox for the infrastructure layer, containers in Kubernetes on top of those VMs.

### Q8: What is live migration and when would you use it?

Moving a running VM between physical hosts without downtime. Requires shared or replicated storage between hosts. I've seen this in Huawei FusionCompute, and I hit the memory ballooning issue during migration in my VMware PoC — the RAM didn't release immediately on the source host after migration.

**My first spoken attempt (May 10):** Got the core right — cold migration = shutdown VM, move it, downtime. Live migration = both hosts up, shared storage, compute reassigned, no downtime. Correctly identified shared storage as the key enabler — disk doesn't move, only compute assignment changes. Without shared storage, disk has to move too which takes time. The only gap: how memory state transfers (answer: iterative memory page copy while VM runs, brief freeze at the end to sync final dirty pages + CPU state). Not expected at mid-level interviews.

### Q9: How does KVM work under the hood?

KVM is a Linux kernel module that turns the host into a Type 1 hypervisor. QEMU handles device emulation on top. Proxmox is a management layer wrapping KVM/QEMU with a web UI, backup, clustering, and API. That's what I run daily.

**My first spoken attempt (May 10):** Didn't know this one. Honest gap — never studied the KVM internals. Interview redirect: "I've used KVM-based hypervisors but I haven't gone deep on the kernel module internals yet. What I can speak to is how I've operated Proxmox which runs on KVM." Redirects to strength without lying.

### Q10: What is resource overcommitment and what are the risks?

Allocating more vCPU or RAM than physically exists. CPU overcommit is usually safe — the hypervisor time-slices. RAM overcommit is risky — leads to swapping and OOM kills. I dealt with this directly: my dev server has 24 GB with ~22 GB allocated, only 2 GB buffer. Had to tune workload sizes multiple times based on real pressure.

**My first spoken attempt (May 10):** Got it right and went deeper than expected. Explained why overcommit works (workloads rarely peak simultaneously, idle resources are waste). Named the risk (contention when multiple VMs peak together). Identified the solution for critical workloads — dedicated/reserved allocation. Added resource pools with priority rules from vCenter/vApp experience (shares, reservations, limits). Even gave a senior-level parallel — Java heap pre-allocation as same pattern at application level. Complete answer.

### Q11: What's the difference between a backup and a snapshot?

Snapshot is a point-in-time state of the disk using copy-on-write. It stays on the same storage and depends on the original disk — if the storage dies, the snapshot dies with it. Also degrades performance if kept too long. Backup is a full independent copy on separate storage. Slower to create but survives original storage failure. I have both in the project — Proxmox backup jobs to the NAS for workload-level protection. In the VMware PoC I used Veeam community edition for backups, which was limited to 10 VMs per job.

**My first spoken attempt (May 10):** Detailed and correct. Snapshot = hypervisor-level, dependency-chained, not portable, chain corruption makes it unusable — proved with real VMware Workstation PoC experience where chain corruption happened. Backup = full independent image, portable, restorable to different VM ID, can extract individual files. Also identified incremental backups as middle ground (faster than full, less risk than snapshots) from Veeam experience, and correctly flagged the tradeoff: building incrementals on top of corrupted mid-level data is risky. Connected back to project decision (Proxmox full backups to NAS). Complete and experience-backed.

### Q12: Where does a container runtime like Docker sit relative to hypervisor types?

Docker isn't a hypervisor at all. It sits in a similar position to Type 2 — runs on top of a host OS — but it doesn't virtualize hardware. Instead it shares the host kernel directly, using namespaces and cgroups for isolation. So it's lighter than both hypervisor types but with weaker isolation. In my Huawei work, the IVS3800 runs exactly this way — physical server, host Linux OS, Docker installed, application containers inside. No hypervisor layer at all.

**My first spoken attempt (May 10):** Answered this naturally as part of Q6. Described the IVS3800 architecture correctly — physical server with Docker host running containers. Identified that containers share the host kernel with no hypervisor layer, making them lighter but less isolated.

---

### Huawei-specific virtualization (if they ask about FusionCompute or storage from CV)

### Q13: Tell me about a time you diagnosed a performance degradation in a virtualization environment.

*(Draw from real Huawei FusionCompute cases — CPU contention, memory pressure, storage I/O bottlenecks, network saturation. Walk through: how you noticed, what tools you used, what the root cause was, how you resolved it.)*

> Practice: pick one real case you remember well and rehearse the story. Structure: symptom → investigation → root cause → fix.

### Q14: Tell me about a time a virtualization environment crashed unexpectedly.

*(Draw from real Huawei FusionCompute cases — OOM kills, host crash, VM sudden death, config errors causing outage. Walk through: how it presented, how you triaged under SLA pressure, what the root cause was, what you did to prevent recurrence.)*

> Practice: pick one real crash case. Structure: what broke → how you found out → what you did → what you learned.

### Q15: What's a LUN, what's a filesystem, and how does storage provisioning work from pool to host connectivity?

A storage pool is the raw capacity — physical disks grouped together (RAID, etc.). A LUN (Logical Unit Number) is a logical slice carved out of that pool — it's what the host sees as a "disk." A filesystem (ext4, XFS, NTFS) is created on top of the LUN so the OS can organize files. The full chain: physical disks → pool → LUN → present to host (via iSCSI, FC, or NFS) → host sees it as a block device → create filesystem → mount.

In Huawei I did this under SLA pressure — pool creation, LUN provisioning, filesystem creation, and host connectivity assignment (mapping which host can access which LUN). The connectivity part is critical for security — you don't want every host seeing every LUN.

> This is from HCIP Storage cert + real TAC work. The key differentiator in interview: you've done this operationally under pressure, not just in a lab.

---

### Q16: What is thin provisioning vs thick provisioning?

Thin provisioning allocates disk space on demand — a VM disk says 100GB but only uses what it actually writes, maybe 20GB. The rest is available to other VMs until it's needed. Thick provisioning reserves the full space upfront — 100GB is locked immediately. Thin is more efficient for space utilization, thick is safer for performance-critical workloads because the space is guaranteed. I use thin provisioning on Proxmox VMs — with limited NVMe storage across many VMs, thick would exhaust the disk immediately.

> Risk of thin: if all VMs grow simultaneously and total usage exceeds physical storage, you hit overcommitment at the storage layer. Same concept as RAM overcommitment but for disk.

### Q17: How do you monitor your hypervisor health?

I have a custom IO storm watchdog script running on the Proxmox host. It detects IO cascade sources or stuck-CPU VMs, auto-resets them, and sends email alerts for both the incident and the recovery. On top of that, there are thermal and power monitors under `proxmox/disaster_recovery/` for hardware-level health. The Proxmox hosts also expose metrics that feed into the observability stack — but the watchdog is the safety net that acts before the monitoring stack can even alert.

### Q18: What is RAID and what levels do you know?

RAID combines multiple disks for redundancy or performance. The common levels:

- RAID 0 — striping, no redundancy. Fast but one disk dies and everything is lost.
- RAID 1 — mirroring. Two disks, same data on both. One can die and you keep running. This is what my NAS uses — 2x2TB mirrored.
- RAID 5 — striping with parity across 3+ disks. One disk can fail. Good balance of space and safety.
- RAID 6 — like RAID 5 but with double parity. Two disks can fail. Needs 4+ disks.
- RAID 10 — mirrors plus striping. Needs 4+ disks. Best performance with redundancy but uses half the total capacity.

> If asked "which would you use in production?" — depends on the workload. Database with heavy writes: RAID 10. General file storage: RAID 5 or 6. Backup target where space matters: RAID 5. My lab NAS: RAID 1 because I only have 2 drives.

### Q19: What is NFS and how does it work?

NFS (Network File System) is a protocol that lets a client mount a remote directory over the network as if it's local. The NFS server exports a directory, the client mounts it. All reads and writes go over the network to the server's disk. It's stateless in NFSv3 (each request is independent), stateful in NFSv4 (server tracks open files and locks). I use NFS for shared storage between my Proxmox hosts and Kubernetes workers — the NAS exports folders, the workers mount them via the NFS CSI driver so pods get PersistentVolumes backed by the NAS.

> Common follow-ups: "What port does NFS use?" — 2049. "What's the difference between NFSv3 and NFSv4?" — v4 is stateful, uses single port (2049), has built-in security (Kerberos support), no need for rpcbind/portmapper like v3.
>
> Gap: review the actual NFS export config on the NAS and the mount options used by the CSI driver. Revisit during Chunk 7 (Kubernetes).

### Q20: What is the difference between block storage, file storage, and object storage?

- **Block storage** — raw disk blocks, no filesystem. The OS sees it as a disk and creates its own filesystem on top. Fast, used for databases and VMs. Examples: LUNs via iSCSI/FC, EBS volumes in AWS, the local NVMe in my Proxmox hosts.
- **File storage** — shared filesystem over the network. Multiple clients can read/write the same files. Simpler but slower than block. Examples: NFS, SMB/CIFS. My NAS serves NFS shares to Proxmox and K8s workers.
- **Object storage** — flat namespace, each object has a key, metadata, and data. No hierarchy, no mount. Accessed via API (HTTP). Scales massively. Examples: S3, my etcd backups go to S3.

> When would you use each: block for databases/VMs that need raw performance, file for shared access across multiple nodes (like K8s PVs), object for backups/logs/artifacts that don't need filesystem semantics. I use all three in my project.