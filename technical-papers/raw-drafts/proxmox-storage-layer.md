Proxmox Storage Layer — How the Hypervisor Manages Storage
============================================================

Traces how Proxmox adds, mounts, and serves storage to VMs.
Covers local LVM thin pool, NFS shared storage, content types,
and the I/O path from VM write to physical disk.


### Where Proxmox Stores Storage Config

NOT in /etc/fstab. Proxmox uses its own config:

    /etc/pve/storage.cfg

/etc/pve/ is special — it's a cluster-aware FUSE filesystem (pmxcfs)
backed by corosync. when you add storage on one node, every node
in the cluster sees it instantly. fstab is per-node, storage.cfg
is cluster-wide.

Example from a real setup:

    dir: local
        path /var/lib/vz
        content backup,snippets,iso,vztmpl

    lvmthin: local-lvm
        thinpool data
        vgname pve
        content images,rootdir

    nfs: nas-iso
        export /volume1/shared-iso
        path /mnt/pve/nas-iso
        server 10.0.40.120
        content iso,vztmpl
        nodes pve-prod

    nfs: nas-prod-data
        export /volume1/prod-storage
        path /mnt/pve/nas-prod-data
        server 10.0.40.120
        content images,rootdir,backup
        nodes pve-prod

    nfs: nas-backups
        export /volume1/Backups
        path /mnt/pve/nas-backups
        server 10.0.40.120
        content backup,rootdir
        nodes pve-prod


### What Happens When You Add NFS Storage via Web UI

    click Datacenter → Storage → Add → NFS → fill form → click Add
      |
      +-- browser sends API call to pveproxy (HTTPS, port 8006)
      |
      +-- pveproxy validates and writes entry to /etc/pve/storage.cfg
      |
      +-- pmxcfs replicates config to all cluster nodes via corosync
      |     (every node sees the new storage immediately)
      |
      +-- pvesm (storage manager) on each relevant node:
      |     mount -t nfs 10.0.40.120:/volume1/prod-storage /mnt/pve/nas-prod-data
      |     → same kernel NFS flow (TCP:2049, ARP, frame, VLAN 40, switch, NAS)
      |     → see nfs-vm-read-trace.md for full network trace
      |
      +-- mount done, storage appears as active in web UI


### Content Types — What Proxmox Expects in Each Storage

The content type dropdown is critical. it tells Proxmox what this storage
is used for and which subdirectory structure to create and look at:

    content type        subdirectory Proxmox looks at
    ─────────────────────────────────────────────────
    iso                 template/iso/
    vztmpl              template/cache/
    backup              dump/
    images (VM disks)   images/<vmid>/
    rootdir (LXC)       rootdir/<vmid>/
    snippets            snippets/

Example for nas-iso (content: iso,vztmpl):

    /mnt/pve/nas-iso/                    ← NFS mount point
      template/
        iso/                              ← put ISO files HERE
          rocky-9.4.iso                   ← Proxmox sees this in the ISO browser
          ubuntu-24.04.iso
        cache/                            ← container templates go HERE
          rocky-10-default.tar.xz

    if you put an ISO in the root of the share instead of template/iso/,
    Proxmox won't see it. it only looks in the expected subdirectory.

Example for nas-prod-data (content: images,rootdir,backup):

    /mnt/pve/nas-prod-data/              ← NFS mount point
      images/
        1001/                             ← VM 1001 (FreeIPA)
          vm-1001-disk-1.raw              ← active data disk
        1010/                             ← VM 1010 (k8s-master1)
          ...
      dump/                               ← VZDump backups
      rootdir/                            ← LXC container rootdirs


### The Physical Disk Layout — LVM and Thin Pools

When Proxmox is installed, it partitions the disk and sets up LVM:

    Physical disk (NVMe SSD, 476.9G)
      |
      +-- nvme0n1p1 (1M)    → BIOS boot
      +-- nvme0n1p2 (1G)    → EFI, mounted at /boot/efi
      +-- nvme0n1p3 (475.9G) → LVM Physical Volume
           |
           +-- Volume Group: pve (pool of all available space)
                |
                +-- pve-swap   (8G)    → swap
                |
                +-- pve-root   (96G)   → ext4, mounted as /
                |     Proxmox OS lives here.
                |     /var/lib/vz ("local" storage) is just a directory here.
                |
                +-- pve-data   (250G)  → LVM thin pool = "local-lvm"
                      |
                      +-- vm-1001-disk-0  (25G)  ← FreeIPA OS disk
                      +-- vm-2001-disk-0  (10G)  ← ansible
                      +-- vm-2001-disk-1  (5G)
                      +-- vm-1010-disk-0  (25G)  ← k8s-master1
                      +-- vm-1011-disk-0  (25G)  ← k8s-master2
                      +-- vm-1012-disk-0  (25G)  ← k8s-master3
                      +-- vm-1020-disk-0  (25G)  ← k8s-worker1
                      +-- vm-1021-disk-0  (25G)  ← k8s-worker2
                      +-- vm-1022-disk-0  (25G)  ← k8s-worker3
                      +-- vm-9000-disk-0  (20G)  ← golden image
                      +-- ... etc


### LVM Concepts

    WITHOUT LVM (traditional partitions):
      physical disk → partition 1 (fixed size, hard to resize)
                   → partition 2 (fixed size, hard to resize)
      want to resize? rebuild everything.

    WITH LVM:
      Physical Volume (PV)  = the raw partition (nvme0n1p3)
      Volume Group (VG)     = pool of all PVs combined (pve)
      Logical Volume (LV)   = virtual partition, flexible size

      want to resize? just change the LV boundary. no rebuild.


### Thin Provisioning

    regular LV:  "give me 25G" → 25G allocated on disk immediately
    thin LV:     "give me 25G" → labeled as 25G, uses space only when written

    vm-1001-disk-0 says 25G, but if the VM only wrote 8G,
    only 8G of physical space is consumed in the thin pool.

    this is why VMs can add up to more than 250G in labels
    without running out — as long as actual written data fits.

    risk: if actual writes exceed the thin pool size → I/O errors.
    monitor with: lvs -o lv_name,lv_size,data_percent pve


### "local" vs "local-lvm"

    "local" (dir: local)
      → path: /var/lib/vz (a directory on pve-root, ext4)
      → stores: ISOs, templates, backups, snippets
      → it's a folder, nothing special

    "local-lvm" (lvmthin: local-lvm)
      → thin pool: pve/data
      → stores: VM disk images, LXC rootdirs
      → block storage — each VM disk is a thin logical volume
      → not a filesystem, no files, just raw block devices

    both live on the same physical disk, different LVM logical volumes.


### How VMs See Their Disks

The VM doesn't know what storage backend is used. It sees virtual
block devices through the VirtIO SCSI controller:

    Proxmox UI              inside VM     actual backend
    ──────────────────────────────────────────────────────────────
    scsi0 (local-lvm)       /dev/sda      /dev/pve/vm-1001-disk-0 (thin LV)
    scsi1 (nas-prod-data)   /dev/sdb      NFS file: images/1001/vm-1001-disk-1.raw
    cloudinit (ide2)        /dev/sr0      ISO image with cloud-init config

    the VM treats sda and sdb identically — just block devices.
    it has no idea sda is a local thin LV and sdb is NFS-backed.
    QEMU/KVM handles the difference.


### I/O Path — Writing to Each Disk Type

VM writes to OS disk (local-lvm, thin LV):

    VM app: write("file.txt", data)
      +-- guest kernel: ext4 → translates to block writes
          +-- guest virtio-scsi driver: "write blocks to /dev/sda"
              +-- virtqueue ring buffer → KVM/QEMU intercepts
                  +-- QEMU: "sda = /dev/pve/vm-1001-disk-0" (thin LV)
                      +-- writes directly to block device
                          +-- LVM thin pool: allocates physical blocks on demand
                              +-- NVMe driver → physical SSD I/O → done

    path: VM → virtio → QEMU → thin LV → physical SSD
    no network involved, purely local I/O.

VM writes to data disk (NFS-backed, raw image file):

    VM app: write("data.txt", data)
      +-- guest kernel: ext4 → translates to block writes
          +-- guest virtio-scsi driver: "write blocks to /dev/sdb"
              +-- virtqueue ring buffer → KVM/QEMU intercepts
                  +-- QEMU: "sdb = /mnt/pve/nas-prod-data/images/1001/vm-1001-disk-1.raw"
                      +-- QEMU writes to the raw image FILE
                          +-- file lives on NFS mount
                              +-- Proxmox kernel NFS client: WRITE RPC
                                  +-- TCP:2049 → IP → ARP → frame
                                      +-- VLAN 40 → switch → NAS
                                          +-- NAS kernel: writes to filesystem
                                              +-- RAID 1 (mirror): controller writes
                                              |   to BOTH physical disks simultaneously
                                              |   → disk 1: write block
                                              |   → disk 2: write same block
                                              |   → both confirm → write acknowledged
                                              |   → if one disk fails, other has full copy

    path: VM → virtio → QEMU → raw file → NFS → network → NAS → RAID 1 → both disks
    crosses the network, slower than local.

VM mounts NFS directly inside the guest (k8s node scenario):

    VM app: write to /mnt/nfs-data/file.txt
      +-- guest kernel NFS client: WRITE RPC
          +-- TCP:2049 → IP → out VM's own eth1
              +-- VLAN 40 → switch → NAS
                  +-- NAS kernel → filesystem → RAID 1 → both disks

    path: VM → NFS client → network → NAS → RAID 1 → both disks
    no QEMU involved — the VM talks to NFS directly.
    this is what k8s nodes do for PV mounts.

    difference from NFS-backed VM disk:
      NFS VM disk:     VM → QEMU → NFS (QEMU mediates, VM doesn't know it's NFS)
      NFS direct mount: VM → NFS (VM knows it's NFS, talks to NAS itself)


### Boot Sequence — How Proxmox Mounts Storage at Start

    node boots
      +-- systemd starts Proxmox services
          +-- pvedaemon reads /etc/pve/storage.cfg
              +-- for each NFS entry:
              |     mount -t nfs server:export /mnt/pve/<name>
              |     → if NAS reachable: mount succeeds, storage active
              |     → if NAS unreachable: mount fails, storage shows "inactive"
              |       Proxmox keeps retrying. node boots fine. doesn't hang.
              |
              +-- for local-lvm:
              |     thin pool already active (LVM activates during boot)
              |     no mount needed, just register with pvesm
              |
              +-- for local (dir):
                    /var/lib/vz is on root filesystem, already mounted
                    just register with pvesm

    advantage over fstab: Proxmox handles NFS mount failures gracefully.
    fstab with a dead NAS = boot hangs. storage.cfg = boot continues,
    storage marked inactive, retry in background.
