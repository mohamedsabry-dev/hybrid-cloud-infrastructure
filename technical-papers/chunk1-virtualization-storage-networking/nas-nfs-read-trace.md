NFS Read — Full Stack Trace (Summary)
======================================

app calls read("/mnt/data/text.txt")
  → libc read() syscall → traps into kernel space
    → VFS: resolves path → /mnt/data is NFS mount → delegates to NFS client
      → NFS client: LOOKUP(root_handle, "text.txt") → server returns file_handle + attrs
      → NFS client: READ(file_handle, offset=0, count=4096) → queues RPC

→ RPC layer serializes request into XDR binary format
  → hands to TCP → builds segment (src port ephemeral, dst port 2049)
    → hands to IP → builds packet (src 10.0.40.11, dst 10.0.40.120, proto TCP)
      → kernel checks routing table: 10.0.40.0/24 dev eth1 scope link
        → same subnet → no gateway → deliver directly via eth1

→ IP layer needs L2 destination before it can send
  → calls neighbour subsystem → checks ARP cache for 10.0.40.120
    → cache miss → builds ARP request (who has .120? tell .11)
      → broadcast frame (dst MAC ff:ff:ff:ff:ff:ff) → out eth1
        → NAS kernel receives → replies: ".120 is at aa:bb:cc:dd:ee:ff"
          → VM kernel caches entry (TTL ~60s) → resumes send

→ kernel builds Ethernet frame
  → dst MAC: aa:bb:cc:dd:ee:ff → src MAC: 11:22:33:44:55:66
    → EtherType: 0x0800 (IPv4) → payload: [IP [TCP [XDR [NFS READ]]]]
      → passes to virtio-net driver → writes to virtqueue ring buffer
        → hypervisor (KVM/QEMU) picks up → injects into tap device

→ tap device feeds into vmbr1 (Proxmox Linux bridge, VLAN-aware)
  → bridge checks VM port config → VLAN tag 40 assigned to this tap
    → inserts 4-byte 802.1Q header (TPID 0x8100, VID 40) into frame
      → bridge FDB (forwarding database): dst MAC learned on port stor0
        → forwards tagged frame out stor0 (physical NIC bound to bridge)
          → NIC driver DMA → frame hits copper/fiber → travels to switch

→ physical switch receives frame on port 5 (trunk, VLAN 40 allowed)
  → reads 802.1Q tag → VLAN 40 → frame stays in VLAN 40 domain
    → reads dst MAC aa:bb:cc:dd:ee:ff → looks up CAM table
      → CAM entry: aa:bb:cc:dd:ee:ff → port 7 (learned from prior NAS traffic)
        → port 7 config: access port, untagged VLAN 40
          → strips 802.1Q header → sends bare frame out port 7
  → any untagged frame on trunk ports → assigned to VLAN 99 (dead-drop)
    → VLAN 99 connected to nothing → frame dropped
    → blocks accidental VLAN leaks + double-tag hopping attacks

→ NAS NIC receives untagged frame → NIC driver raises interrupt
  → kernel netif_receive_skb() → allocates sk_buff → strips Ethernet header
    → EtherType 0x0800 → passes to IP layer → validates, strips IP header
      → proto TCP → passes to TCP layer → reassembles segment, strips header
        → dst port 2049 → socket owned by nfsd → delivers RPC payload
          → nfsd unmarshals XDR → NFS READ request extracted

→ nfsd authentication: reads src IP from socket → 10.0.40.11
  → checks /etc/exports: "/shared 10.0.40.11(rw,sync,no_root_squash)"
    → IP matches → client identity confirmed (no token, no cert — IP only)
      → authorization: export says rw → READ is allowed
        → checks inode permissions: uid/gid from RPC vs file owner/mode bits
          → access granted → VFS reads blocks from disk → fills reply buffer

→ nfsd builds NFS READ reply (file bytes + status OK)
  → RPC layer serializes to XDR → TCP → IP (src .120, dst .11)
    → ARP cache: .11 = 11:22:33:44:55:66 → builds frame → out NAS NIC
      → switch: CAM → port 5 → tags VLAN 40 (trunk) → sends
        → Proxmox stor0 → vmbr1 → strips tag → tap → virtqueue → VM eth1
          → kernel: IP → TCP → RPC reply → NFS client → VFS → app gets bytes

---

Two NFS paths — same NAS, different entry points:

  Direct NFS mount (this trace, k8s nodes):
    VM app → guest kernel NFS client → WRITE RPC → TCP:2049 → NAS
    VM knows it's NFS. VM's kernel handles the NFS protocol.

  QEMU-mediated NFS (Proxmox storage backend):
    VM app → guest ext4 → virtio-scsi → QEMU intercepts
      → QEMU: "sdb = /mnt/pve/nas-prod-data/images/1001/vm-1001-disk-1.raw"
        → writes to raw image FILE on NFS mount
          → Proxmox host kernel NFS client → WRITE RPC → TCP:2049 → NAS
    VM thinks it's a local SCSI disk. QEMU translates to NFS on the host side.
