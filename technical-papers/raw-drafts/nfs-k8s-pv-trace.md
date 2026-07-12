NFS on Kubernetes — Raw PV Lifecycle (Scenario 1)
===================================================

Scenario: raw NFS PV with reclaimPolicy: Retain.
No CSI driver. Admin creates everything manually.
Traces from "nothing exists" to "pod running" to "full cleanup."

Underlying NFS network trace (kernel → TCP/IP → ARP → VLAN 40 → switch → NAS)
is identical to the VM-level trace — see nfs-vm-read-trace.md.


### PV and PVC — What They Actually Are

PV and PVC are pure API objects stored in etcd. Database records, not mounts.

    PV  = admin declares "this storage exists at this address"
    PVC = developer declares "I need storage with these specs"
    binding = k8s matches PVC to PV in etcd (1:1, no slicing)

    PV says 50Gi, PVC asks 10Gi → PV is fully claimed.
    remaining 40Gi is wasted. k8s doesn't subdivide a PV.
    one PV, one PVC, one binding. always.

    capacity field is a scheduling label, not enforcement.
    NFS has no quota at protocol level — pod can write past the declared size.
    only block storage (Ceph, iSCSI, EBS) enforces real size limits.


### The Two Config Files in k8s Context

PV (admin writes):

    apiVersion: v1
    kind: PersistentVolume
    metadata:
      name: nfs-data
    spec:
      capacity:
        storage: 50Gi                    ← label, not enforced on NFS
      accessModes:
        - ReadWriteMany
      persistentVolumeReclaimPolicy: Retain
      mountOptions:
        - soft                            ← same flags as fstab
        - timeo=10
        - retrans=3
      nfs:
        server: 10.0.40.120
        path: /shared/app-data

PVC (developer writes):

    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: app-data
    spec:
      accessModes:
        - ReadWriteMany
      resources:
        requests:
          storage: 10Gi                   ← matched against PV capacity

    PVC doesn't know the NFS server IP or path.
    it just says "give me 10Gi RWX" — k8s finds a matching PV.

Pod (developer writes):

    spec:
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: app-data
      containers:
        - name: app
          volumeMounts:
            - name: data
              mountPath: /app/data


### Full Lifecycle — Phase by Phase


PHASE 1 — Admin prepares storage (manual, outside k8s)

    admin SSH to NAS:
      → mkdir /shared/app-data
      → chown 1000:1000 /shared/app-data
      → verify export rule in /etc/exports:
          /shared  10.0.40.0/24(rw,sync,no_root_squash)

    k8s knows nothing about this. just a folder on a disk.


PHASE 2 — Admin creates PV and PVC (order doesn't matter)

    PV and PVC can be created in any order.
    PV controller watches for unbound PVCs and available PVs continuously.
    whichever appears second triggers the match.

    kubectl apply -f pv.yaml
      → kubectl sends YAML to API server (HTTPS, port 6443)
        → API server validates schema
          → writes PV object to etcd
            → PV status: Available

    nothing happens on any node.
    nothing happens on the NAS.
    no mount, no kernel involvement.
    just a database record in etcd.

    kubectl apply -f pvc.yaml
      → API server writes PVC to etcd
        → PV controller (inside kube-controller-manager) wakes up
          → watches: "new unbound PVC, wants 10Gi RWX"
          → scans PV list in etcd
          → PV nfs-data: 50Gi RWX Available — matches
          → updates both objects in etcd:
              PVC.spec.volumeName = nfs-data
              PV.spec.claimRef = PVC app-data
              PV.status = Bound
              PVC.status = Bound

    (if PVC was created first, it would sit Pending until PV appears —
     then PV controller matches them the same way. same result either way.)

    still nothing on any node or NAS.
    just two linked records in etcd.


PHASE 4 — Developer creates Pod referencing PVC

    kubectl apply -f pod.yaml
      |
      +-- API server stores pod in etcd, status: Pending
      |
      +-- Scheduler wakes up:
      |     "pod myapp is Pending, needs scheduling"
      |     → filters nodes (CPU, memory, taints, affinity)
      |     → scores remaining nodes
      |     → picks worker-01
      |     → updates pod in etcd: nodeName = worker-01
      |
      +-- Kubelet on worker-01 wakes up:
      |     watches API server, sees "new pod myapp assigned to me"
      |     reads pod spec:
      |       volumes: [PVC app-data]
      |       containers: [image: myapp, volumeMounts: [/app/data]]
      |
      +-- VOLUME PHASE (before container exists):
      |     +-- resolves: PVC app-data → PV nfs-data
      |     +-- reads PV: type=nfs, server=10.0.40.120,
      |     |     path=/shared/app-data, mountOptions=[soft,timeo=10]
      |     +-- mkdir /var/lib/kubelet/pods/<pod-uid>/volumes/kubernetes.io~nfs/nfs-data/
      |     +-- mount -t nfs -o soft,timeo=10 10.0.40.120:/shared/app-data \
      |     |     /var/lib/kubelet/pods/<pod-uid>/volumes/kubernetes.io~nfs/nfs-data/
      |     |
      |     |   ═══ VM-LEVEL NFS TRACE STARTS HERE ═══
      |     |   kernel: RPC → XDR → TCP (port 2049) → IP (src .11, dst .120)
      |     |   → routing: same subnet → direct via eth1
      |     |   → ARP: resolve .120 MAC → cache
      |     |   → frame: dst MAC, src MAC, EtherType 0x0800
      |     |   → virtio-net → virtqueue → KVM/QEMU → tap device
      |     |   → vmbr1: VLAN tag 40 → FDB → out stor0 → DMA → wire
      |     |   → switch: 802.1Q tag 40 → CAM table → port 7 → strip tag
      |     |   → NAS NIC: interrupt → sk_buff → IP → TCP → nfsd
      |     |   → nfsd: src IP check → /etc/exports → mount granted
      |     |   → root file handle returned → VFS registers mount
      |     |   (full trace: see nfs-vm-read-trace.md)
      |     |   ═══════════════════════════════════════
      |     |
      |     +-- volume ready. container doesn't exist yet.
      |
      +-- SANDBOX PHASE:
      |     +-- kubelet → containerd: "create pod sandbox"
      |     +-- containerd creates pause container
      |     +-- CNI plugin sets up network namespace → pod gets IP
      |     +-- sandbox ready. app container doesn't exist yet.
      |
      +-- CONTAINER PHASE:
      |     +-- kubelet → containerd: "create container from image myapp"
      |     +-- containerd pulls image (if not cached)
      |     +-- containerd creates container with OCI spec including:
      |     |     bind-mount: kubelet volume dir → container's /app/data
      |     +-- mount --bind /var/lib/kubelet/pods/.../nfs-data/ \
      |     |     → /var/run/containers/<container-id>/rootfs/app/data
      |     +-- starts container process
      |
      +-- Pod status: Running
          container sees /app/data as normal directory
          reads/writes go through: VFS → NFS client → TCP → NAS
          container has no idea it's NFS or a bind mount


PHASE 5 — Pod deleted

    kubectl delete pod myapp
      |
      +-- API server marks pod for deletion
      |
      +-- kubelet on worker-01:
      |     +-- sends SIGTERM to container process
      |     +-- waits terminationGracePeriodSeconds (default 30s)
      |     +-- sends SIGKILL if still alive
      |     +-- containerd removes container
      |     +-- containerd removes sandbox (pause container)
      |     |
      |     +-- VOLUME CLEANUP:
      |     |     +-- umount /var/lib/kubelet/pods/<pod-uid>/volumes/.../nfs-data/
      |     |     |     → kernel sends NFS UMNT RPC to NAS
      |     |     |     → NAS releases file handles for this client
      |     |     +-- rmdir the kubelet volume directory
      |     |
      |     +-- pod gone from this node
      |
      +-- PVC: still exists in etcd, still Bound to PV
      +-- PV: still exists in etcd, still Bound
      +-- NAS: /shared/app-data still there, all data intact
      |
      +-- another pod referencing the same PVC will get the same data
          (kubelet re-mounts when new pod is scheduled)


PHASE 6 — PVC deleted (reclaimPolicy: Retain)

    kubectl delete pvc app-data
      |
      +-- API server deletes PVC from etcd
      |
      +-- PV controller sees: PV nfs-data lost its bound PVC
      |     → checks reclaimPolicy: Retain
      |     → PV status: Released (not Available)
      |
      |   Released means:
      |     "this PV had data from a previous claim.
      |      admin must decide what to do."
      |
      |   PV is NOT reusable. new PVCs will NOT bind to it.
      |   it's stuck in Released until admin intervenes.
      |
      +-- NAS: /shared/app-data still there. data intact.
      |     → k8s cannot delete it
      |     → kubelet only knows mount/unmount
      |     → PV controller only manages etcd records
      |     → no component in k8s can SSH to NAS and rm -rf
      |
      +-- Admin must manually:
            option A — keep data, reuse PV:
              kubectl edit pv nfs-data → remove spec.claimRef
              → PV goes back to Available → new PVC can bind

            option B — full cleanup:
              1. SSH to NAS: rm -rf /shared/app-data
              2. kubectl delete pv nfs-data
              → everything gone


### Kubelet Recovery — What Happens on Node Reboot

    no fstab entry exists for NFS mounts. kubelet manages them.

    node reboots:
      → all mounts gone, all containers gone
      → kubelet starts, connects to API server
      → API server: "pod myapp belongs on you"
      → kubelet reads pod spec → PVC → PV → NFS details
        → creates fresh NFS mount (new mount, same VM-level trace)
        → creates new sandbox (new pause container, new network namespace)
        → creates new container from image (new container ID, new PID)
        → bind-mounts volume into new container
      → pod back, same data — but everything else is new
         only the data on NAS survived, the container is built from scratch

    kubelet reconciliation loop:
      "what pods should be on me? → are their volumes mounted? →
       no? mount them. are containers running? no? start them."

    etcd = the brain (stores what should exist)
    kubelet = the hands (makes it real, re-makes after restart)
    NAS = the disk (data persists regardless of k8s state)



Scenario 2 — CSI NFS Driver, reclaimPolicy: Delete
----------------------------------------------------

CSI driver handles what the admin did manually in scenario 1:
  - creates subdirectory on NAS (no SSH needed)
  - creates PV automatically (no YAML needed)
  - deletes subdirectory on NAS when PVC is deleted (full cleanup)

Two pod types run in the cluster to make this work:

    CSI Controller (Deployment, 1 replica):
      → watches PVC events from API server
      → creates/deletes subdirectories on NAS
      → creates/deletes PV objects in etcd
      → must run on a node with network access to NAS (storage VLAN)

    CSI Node (DaemonSet, one pod per worker):
      → listens on gRPC unix socket on each node
      → kubelet calls it to mount/unmount instead of doing it directly
      → replaces kubelet's built-in NFS mount logic


### StorageClass — The Recipe

    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: nfs-delete
    provisioner: nfs.csi.k8s.io
    parameters:
      server: 10.0.40.120
      share: /volume1/k8s-prod
    reclaimPolicy: Delete
    volumeBindingMode: Immediate

    StorageClass = the bridge between "developer wants storage"
    and "which software provisions it, where, and with what rules."

    NFS server details live here ONCE.
    no need to repeat them in every PV — CSI reads them from here.


### Full Lifecycle — Phase by Phase


PHASE 0 — CSI driver already running in cluster

    CSI controller pod (on a node with storage network access):
      +-- watches: PVC create/delete events
      +-- can mount NFS on itself temporarily to mkdir/rmdir

    CSI node pods (one per worker):
      +-- registered with kubelet via gRPC socket
      +-- kubelet delegates mount/unmount to them

    StorageClass nfs-delete exists:
      provisioner = nfs.csi.k8s.io
      server = 10.0.40.120
      share = /volume1/k8s-prod


PHASE 1 — Developer creates PVC (no PV needed, no admin needed)

    kubectl apply -f pvc.yaml
      |  (pvc.yaml has: storageClassName: nfs-delete, requests: 10Gi)
      |
      +-- API server stores PVC in etcd, status: Pending
      |
      +-- CSI controller (external-provisioner sidecar) wakes up:
      |     → "new PVC, storageClassName=nfs-delete, that's my provisioner"
      |     → reads StorageClass parameters:
      |         server=10.0.40.120, share=/volume1/k8s-prod
      |
      +-- CSI controller creates subdirectory on NAS:
      |     +-- mounts NFS temporarily on itself:
      |     |     mount -t nfs 10.0.40.120:/volume1/k8s-prod /tmp/provision
      |     +-- mkdir /tmp/provision/pvc-d4f8a2b1-7e3c-4a1f-...
      |     |     (directory name = PVC UUID, unique, never collides)
      |     +-- umount /tmp/provision
      |     +-- directory now exists on NAS: /volume1/k8s-prod/pvc-d4f8a2b1-...
      |
      +-- CSI controller creates PV object via API server:
      |     name: pvc-d4f8a2b1-...
      |     csi:
      |       driver: nfs.csi.k8s.io
      |       volumeHandle: 10.0.40.120#volume1/k8s-prod#pvc-d4f8a2b1-...
      |       volumeAttributes:
      |         server: 10.0.40.120
      |         share: /volume1/k8s-prod
      |         subdir: pvc-d4f8a2b1-...
      |     capacity: 10Gi (from PVC request — still not enforced on NFS)
      |     reclaimPolicy: Delete
      |     claimRef: PVC app-data (pre-bound)
      |
      +-- PV and PVC both set to Bound in etcd
      |
      +-- admin did nothing.
           no manual PV YAML, no SSH to NAS, no mkdir.
           compare scenario 1: admin had to do all three.


PHASE 2 — Developer creates Pod referencing PVC

    kubectl apply -f pod.yaml
      |
      +-- API server stores pod in etcd, status: Pending
      |
      +-- Scheduler: picks worker-01 → updates pod nodeName in etcd
      |
      +-- Kubelet on worker-01 wakes up:
      |     reads pod spec → PVC app-data → PV pvc-d4f8a2b1-...
      |     PV type is CSI (not built-in nfs plugin)
      |
      +-- VOLUME PHASE (kubelet delegates to CSI node plugin):
      |     +-- kubelet does NOT mount directly (unlike scenario 1)
      |     +-- kubelet calls CSI node plugin via local gRPC socket:
      |     |
      |     |   NodePublishVolume(
      |     |     target: /var/lib/kubelet/pods/<pod-uid>/volumes/csi/pvc-d4f8a2b1-.../mount
      |     |     server: 10.0.40.120
      |     |     path: /volume1/k8s-prod/pvc-d4f8a2b1-...
      |     |     options: [soft, timeo=10]
      |     |   )
      |     |
      |     +-- CSI node plugin executes:
      |     |     mount -t nfs -o soft,timeo=10 \
      |     |       10.0.40.120:/volume1/k8s-prod/pvc-d4f8a2b1-... \
      |     |       /var/lib/kubelet/pods/<pod-uid>/volumes/csi/pvc-d4f8a2b1-.../mount
      |     |
      |     |   ═══ VM-LEVEL NFS TRACE FROM HERE ═══
      |     |   kernel → TCP/IP → ARP → frame → VLAN 40 → switch → NAS
      |     |   (identical to scenario 1 and nfs-vm-read-trace.md)
      |     |   ═════════════════════════════════════
      |     |
      |     +-- CSI node returns success to kubelet via gRPC
      |     +-- volume ready. container doesn't exist yet.
      |
      +-- SANDBOX PHASE:
      |     +-- kubelet → containerd: create pod sandbox
      |     +-- containerd creates pause container
      |     +-- CNI plugin: network namespace → pod gets IP
      |     +-- sandbox ready
      |
      +-- CONTAINER PHASE:
      |     +-- kubelet → containerd: create container from image
      |     +-- containerd creates container with OCI spec:
      |     |     bind-mount: kubelet CSI volume dir → container's /app/data
      |     +-- starts container process
      |
      +-- Pod status: Running
          app sees /app/data → reads/writes → NFS RPCs → NAS
          no idea it's NFS, no idea CSI is involved


PHASE 3 — Pod deleted

    kubectl delete pod myapp
      |
      +-- kubelet on worker-01:
      |     +-- SIGTERM → wait gracePeriod → SIGKILL
      |     +-- containerd removes container
      |     +-- containerd removes sandbox
      |     |
      |     +-- VOLUME CLEANUP (via CSI node):
      |     |     +-- kubelet calls CSI node plugin via gRPC:
      |     |     |     NodeUnpublishVolume(target: .../mount)
      |     |     +-- CSI node plugin: umount
      |     |     |     → kernel: NFS UMNT RPC → NAS releases handles
      |     |     +-- returns success to kubelet
      |     |     +-- kubelet removes volume directory
      |     |
      |     +-- pod gone from this node
      |
      +-- PVC still exists in etcd, still Bound
      +-- PV still exists in etcd, still Bound
      +-- NAS: /volume1/k8s-prod/pvc-d4f8a2b1-... still there, data intact


PHASE 4 — PVC deleted (HERE is the big difference from scenario 1)

    kubectl delete pvc app-data
      |
      +-- API server deletes PVC from etcd
      |
      +-- PV controller: PV lost its bound PVC
      |     → checks reclaimPolicy: Delete
      |     → triggers CSI deletion
      |
      +-- CSI controller (external-provisioner) sees: "delete volume"
      |     +-- reads PV volumeAttributes:
      |     |     server=10.0.40.120, share=/volume1/k8s-prod,
      |     |     subdir=pvc-d4f8a2b1-...
      |     |
      |     +-- mounts NFS temporarily on itself:
      |     |     mount -t nfs 10.0.40.120:/volume1/k8s-prod /tmp/provision
      |     |     rm -rf /tmp/provision/pvc-d4f8a2b1-...
      |     |     umount /tmp/provision
      |     |     → directory DELETED from NAS
      |     |
      |     +-- deletes PV object from etcd
      |     |
      |     +-- everything cleaned up:
      |           no PVC in etcd
      |           no PV in etcd
      |           no folder on NAS
      |           like it never existed

    compare scenario 1 (Retain):
      PVC deleted → PV stuck in Released → folder stays on NAS
      admin must SSH to NAS + kubectl delete pv → manual cleanup

    scenario 2 (Delete via CSI):
      PVC deleted → CSI controller removes folder → deletes PV → fully automatic


### Scenario Comparison

                          Scenario 1              Scenario 2
                          Raw PV / Retain         CSI / Delete

    who creates folder    admin (SSH to NAS)      CSI controller (auto)
    who creates PV        admin (kubectl apply)   CSI controller (auto)
    who mounts on node    kubelet (directly)      CSI node (via gRPC)
    who unmounts           kubelet (directly)      CSI node (via gRPC)
    who deletes folder    admin (SSH to NAS)      CSI controller (auto)
    who deletes PV        admin (kubectl delete)  CSI controller (auto)
    StorageClass needed   no                      yes
    capacity enforced     no                      no (still NFS)

    the NFS network trace underneath is identical in both.
    the difference is purely in the k8s orchestration layer.
