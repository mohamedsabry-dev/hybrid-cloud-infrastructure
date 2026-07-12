Proxmox Storage Layer — Summary Trace
=======================================

Adding NFS storage via web UI:

click Datacenter → Storage → Add → NFS → fill form → Add
  → browser sends API to pveproxy (HTTPS:8006)
    → pveproxy writes entry to /etc/pve/storage.cfg
      → pmxcfs replicates to all cluster nodes via corosync
        → pvesm: mount -t nfs 10.0.40.120:/volume1/prod-storage /mnt/pve/nas-prod-data
          → kernel NFS mount (same VM-level trace: TCP:2049, ARP, VLAN 40, switch, NAS)
            → content type determines subdirectory structure:
              iso → template/iso/  |  images → images/<vmid>/  |  backup → dump/

Physical disk layout (Proxmox install):

nvme0n1 (476.9G SSD)
  → nvme0n1p3 → LVM Physical Volume → Volume Group: pve
    → pve-root (96G, ext4, /) → Proxmox OS + /var/lib/vz ("local" storage)
    → pve-swap (8G)
    → pve-data (250G, thin pool) → "local-lvm"
      → thin LVs per VM: vm-1001-disk-0 (25G), vm-1010-disk-0 (25G), ...
        → thin = labeled size, only uses space when actually written

VM write to OS disk (local-lvm):

VM app write → guest ext4 → virtio-scsi → virtqueue → QEMU intercepts
  → QEMU: "sda = /dev/pve/vm-1001-disk-0" (thin LV)
    → writes to block device → thin pool allocates blocks on demand
      → NVMe driver → physical SSD → done
        → purely local, no network

VM write to data disk (NFS-backed):

VM app write → guest ext4 → virtio-scsi → virtqueue → QEMU intercepts
  → QEMU: "sdb = /mnt/pve/nas-prod-data/images/1001/vm-1001-disk-1.raw"
    → writes to raw image FILE on NFS mount
      → Proxmox kernel NFS client: WRITE RPC → TCP:2049
        → ARP → frame → VLAN 40 → switch → NAS disk
          → crosses network, slower than local

VM mounts NFS directly (k8s node scenario):

VM app write → guest kernel NFS client → WRITE RPC → TCP:2049
  → out VM's own eth1 → VLAN 40 → switch → NAS
    → no QEMU involved, VM talks to NAS itself

Boot recovery:

node boots → pvedaemon reads /etc/pve/storage.cfg
  → NFS entries: mount each one → if NAS down, mark inactive, retry in background
    → doesn't hang boot (unlike fstab)
  → local-lvm: thin pool activated by LVM during boot, just register
  → local: /var/lib/vz on root filesystem, already mounted
