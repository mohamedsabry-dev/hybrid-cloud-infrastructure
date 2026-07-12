NFS on a VM — From Config to Wire to Disk
==========================================

### What NFS Is

Object storage (S3) = stateless, one HTTP request per operation, signed per call.
NFS = stateful mount, persistent session, multiple RPC calls per file operation.
Block storage = raw blocks, no file awareness, VM kernel puts a filesystem on top.


### The Two Config Files

Server side — /etc/exports (on the NAS):

    /shared  10.0.40.11(rw,sync,no_root_squash)
    /shared  10.0.40.12(ro,sync)

    This is the access control list.
    Each line = which client IP can mount which export, with what rules.
    NAS GUI (Asustor ADM, Synology DSM, TrueNAS, etc.) writes this file behind the scenes.

Client side — /etc/fstab (on the Linux VM):

    10.0.40.120:/shared   /mnt/data   nfs   defaults,rw   0 0
    |                     |           |     |              | |
    |                     |           |     |              | +-- fsck order (0 = skip)
    |                     |           |     |              +-- dump backup (0 = skip)
    |                     |           |     +-- mount options (local kernel behavior)
    |                     |           +-- filesystem type (loads nfs kernel module)
    |                     +-- local mount point
    +-- remote server:export

    "rw" here = client-side intention, not a permission grant.
    If server says ro, client rw writes will fail at NFS layer (EROFS).
    Both sides must agree.

    "defaults" expands to: rw, suid, dev, exec, auto, nouser, async.

    For resilience, add: _netdev,soft,timeo=10
      _netdev  = needs network first (tells systemd ordering)
      soft     = give up after retries instead of hanging boot
      timeo=10 = 1 second timeout per retry


### Boot Sequence — When the Mount Happens

    BIOS/UEFI
      +-- bootloader
          +-- kernel loads, mounts / (root filesystem)
              +-- systemd starts
                  +-- network target (NIC up, IP assigned)
                      +-- remote-fs.target
                          +-- reads /etc/fstab, finds NFS entries
                          +-- calls mount.nfs
                          +-- kernel loads nfs module
                          +-- connects to NAS, gets root file handle
                          +-- VFS registers mount at /mnt/data
                              +-- boot continues

    NFS mounts happen AFTER networking is up.
    If NAS is unreachable and "soft" is not set, boot hangs here.


### Fixing a Broken fstab (Recovery)

    A typo like "nfsx" instead of "nfs" won't corrupt the file —
    the file is fine, the content is wrong. But it can block boot.

    Fix:
      1. Boot into recovery / single-user mode (GRUB menu)
      2. Root shell arrives, but / is mounted read-only (safety)
      3. mount -o remount,rw /       ← flip / to writable in-place
      4. vi /etc/fstab               ← fix the typo
      5. reboot

    Prevention:
      Always run "mount -a" after editing fstab.
      It tries all entries — catches typos before next reboot.


### NFS File Access — What Happens in the Kernel

    app: read("/mnt/data/text.txt")
      |
      +-- VFS layer: path is under /mnt/data → route to NFS client
          |
          +-- NFS client module builds RPC:
          |     LOOKUP(root_handle, "text.txt")
          |       +-- server returns file_handle + file size
          |
          +-- NFS client:
          |     READ(file_handle, offset=0, count=4096)
          |       +-- server returns 4096 bytes
          |     READ(file_handle, offset=4096, count=4096)
          |       +-- server returns next 4096 bytes
          |
          +-- app gets file contents

    Every operation (lookup, open, read, write, close) = separate RPC call.
    The kernel hides all this — the app just sees a normal read() syscall.


### Network Trace — Full Path From VM to NAS

Environment:
  VM (10.0.40.11) → Proxmox vswitch (vmbr1, VLAN 40) → physical switch → NAS (10.0.40.120)
  No NAT — same subnet, same VLAN, same broadcast domain, purely L2 forwarded.

Step 1 — App to kernel:

    app calls read("/mnt/data/text.txt")
      +-- libc read() syscall → traps into kernel space
          +-- VFS: resolves path → /mnt/data is NFS mount → delegates to NFS client
              +-- NFS client: LOOKUP(root_handle, "text.txt") → server returns file_handle + attrs
              +-- NFS client: READ(file_handle, offset=0, count=4096) → queues RPC

Step 2 — Kernel builds the packet:

    RPC layer serializes request into XDR binary format
      +-- hands to TCP → builds segment (src port ephemeral, dst port 2049)
          +-- hands to IP → builds packet (src 10.0.40.11, dst 10.0.40.120, proto TCP)
              +-- kernel checks routing table: 10.0.40.0/24 dev eth1 scope link
                  +-- same subnet → no gateway → deliver directly via eth1

Step 3 — ARP resolution (endpoints do this, NOT the switch):

    IP layer needs L2 destination before it can send
      +-- calls neighbour subsystem → checks ARP cache for 10.0.40.120
          +-- cache miss → builds ARP request (who has .120? tell .11)
              +-- broadcast frame (dst MAC ff:ff:ff:ff:ff:ff) → out eth1
                  +-- NAS kernel receives → replies: ".120 is at aa:bb:cc:dd:ee:ff"
                      +-- VM kernel caches entry (TTL ~60s) → resumes send

Step 4 — Frame construction (now it's a frame, not just a packet):

    kernel builds Ethernet frame
      +-- dst MAC: aa:bb:cc:dd:ee:ff → src MAC: 11:22:33:44:55:66
          +-- EtherType: 0x0800 (IPv4) → payload: [IP [TCP [XDR [NFS READ]]]]
              +-- passes to virtio-net driver → writes to virtqueue ring buffer
                  +-- hypervisor (KVM/QEMU) picks up → injects into tap device

    Packet = L3 (IP level, has addresses)
    Frame  = L2 (Ethernet level, has MACs, hits the wire)

Step 5 — VM eth1 → Proxmox vswitch:

    tap device feeds into vmbr1 (Proxmox Linux bridge, VLAN-aware)
      +-- bridge checks VM port config → VLAN tag 40 assigned to this tap
          +-- inserts 4-byte 802.1Q header (TPID 0x8100, VID 40) into frame
              +-- bridge FDB (forwarding database): dst MAC learned on port stor0
                  +-- forwards tagged frame out stor0 (physical NIC bound to bridge)
                      +-- NIC driver DMA → frame hits copper/fiber → travels to switch

Step 6 — Physical switch:

    frame arrives on port 5 (trunk, VLAN 40 allowed)
      +-- reads 802.1Q tag → VLAN 40 → frame stays in VLAN 40 domain
          +-- reads dst MAC aa:bb:cc:dd:ee:ff → looks up CAM table
              +-- CAM entry: aa:bb:cc:dd:ee:ff → port 7 (learned from prior NAS traffic)
                  +-- port 7 config: access port, untagged VLAN 40
                      +-- strips 802.1Q header → sends bare frame out port 7

    switch operates at L2 ONLY — never looks at IP addresses.
    switch has a MAC address table (CAM table), NOT an ARP table.

    CAM table (built by passively watching source MACs):
      aa:bb:cc:dd:ee:ff  →  port 7   (learned from NAS traffic)
      11:22:33:44:55:66  →  port 5   (learned from VM traffic)

    Key: switch never does ARP. It learns MACs passively.
         ARP = endpoints (VM kernel, NAS kernel).
         CAM = switch (MAC → physical port mapping).

    VLAN 99 dead-drop:
      trunk ports are configured with native VLAN 99 (unused, connected to nothing).
      any untagged frame arriving on a trunk port gets assigned to VLAN 99 → goes nowhere.
      this prevents untagged traffic from accidentally landing in a real VLAN
      and blocks double-tag VLAN hopping attacks (attacker sends 802.1Q[99][40] —
      switch strips outer tag → VLAN 99, inner tag 40 never reaches VLAN 40 domain).

Step 7 — NAS receives:

    NAS NIC receives untagged frame → NIC driver raises interrupt
      +-- kernel netif_receive_skb() → allocates sk_buff → strips Ethernet header
          +-- EtherType 0x0800 → passes to IP layer → validates, strips IP header
              +-- proto TCP → passes to TCP layer → reassembles segment, strips header
                  +-- dst port 2049 → socket owned by nfsd → delivers RPC payload
                      +-- nfsd unmarshals XDR → NFS READ request extracted

Step 8 — NAS authentication + authorization:

    nfsd authentication: reads src IP from socket → 10.0.40.11
      +-- checks /etc/exports: "/shared 10.0.40.11(rw,sync,no_root_squash)"
          +-- IP matches → client identity confirmed (no token, no cert — IP only)
              +-- authorization: export says rw → READ is allowed
                  +-- checks inode permissions: uid/gid from RPC vs file owner/mode bits
                      +-- access granted → VFS reads blocks from disk → fills reply buffer

Step 9 — Response takes the exact reverse path:

    nfsd builds NFS READ reply (file bytes + status OK)
      +-- RPC layer serializes to XDR → TCP → IP (src .120, dst .11)
          +-- ARP cache: .11 = 11:22:33:44:55:66 → builds frame → out NAS NIC
              +-- switch: CAM → port 5 → tags VLAN 40 (trunk) → sends
                  +-- Proxmox stor0 → vmbr1 → strips tag → tap → virtqueue → VM eth1
                      +-- kernel: IP → TCP → RPC reply → NFS client → VFS → app gets bytes


### Concurrent Writes — Why Shared NFS Breaks Some Apps

NFS locking is advisory — apps must request locks, NFS won't enforce them.

    Safe — different files per writer:
      each replica writes its own log → no conflict

    Dangerous — same file, app expects POSIX locks:
      SQLite, Grafana default DB, embedded databases
      NFS locks are unreliable → silent corruption

    The corruption is NOT at the NAS filesystem level (ext4/xfs is fine).
    It's at the application data level (SQLite B-tree, WAL journal).

What happens with SQLite on shared NFS (e.g. Grafana 3 replicas, 1 PVC):

    Replica 1: acquire fcntl lock → NFS advisory lock → thinks exclusive
    Replica 2: acquire fcntl lock → NFS advisory lock → ALSO thinks exclusive
      (locks lost on network blip, stale after reconnect, not enforced cross-client)

    Replica 1: writes WAL entries, modifies page 47
    Replica 2: reads stale cached page 47 (NFS client-side cache)
    Replica 2: writes its own WAL entries, modifies page 47 differently
    Both commit and checkpoint:
      +-- page 47 has interleaved bytes
      +-- B-tree pointers broken
      +-- "database disk image is malformed"

    What corrupted:                    What was fine:
      x  grafana.db (SQLite pages)       +  NFS protocol (delivered all writes)
      x  grafana.db-wal (torn WAL)       +  NAS filesystem (stored correctly)
      x  grafana.db-shm (stale SHM)      +  disk hardware

Fix: use a real database (PostgreSQL) over TCP for shared state.
     NFS volumes should hold read-only data or per-pod files only.
