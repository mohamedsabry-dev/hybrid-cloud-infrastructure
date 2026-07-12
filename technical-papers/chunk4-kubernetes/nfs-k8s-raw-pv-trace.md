NFS on Kubernetes — Raw PV Lifecycle (Summary Trace)
=====================================================

admin: mkdir /shared/app-data on NAS manually
  → chown 1000:1000, verify /etc/exports allows client IPs
    → k8s knows nothing about this yet

kubectl apply pv.yaml
  → API server validates → stores PV in etcd → status: Available
    → no mount, no kernel, just a database record

kubectl apply pvc.yaml
  → API server stores PVC in etcd
    → PV controller: "PVC wants 10Gi RWX, PV nfs-data offers 50Gi RWX — fits"
      → binds PVC to PV in etcd (1:1, no slicing, remaining 40Gi wasted)
        → still just etcd records, nothing on any node

kubectl apply pod.yaml (references PVC app-data)
  → API server stores pod → status: Pending
    → scheduler: filters/scores nodes → picks worker-01 → writes nodeName to etcd
      → kubelet on worker-01 wakes up: "new pod assigned to me"
        → reads pod spec → PVC app-data → PV nfs-data → NFS server + path + options

→ VOLUME PHASE (before container exists):
  → kubelet: mkdir /var/lib/kubelet/pods/<pod-uid>/volumes/kubernetes.io~nfs/nfs-data/
    → mount -t nfs -o soft,timeo=10 10.0.40.120:/shared/app-data → kubelet volume dir
      → kernel: RPC/XDR → TCP:2049 → IP (.11 → .120) → same subnet, no gateway
        → ARP .120 → frame → virtio → virtqueue → KVM → tap → vmbr1
          → VLAN 40 tag → FDB → stor0 → DMA → wire → switch
            → CAM table → port 7 → strip tag → NAS NIC
              → sk_buff → IP → TCP → nfsd → exports check → mount granted
                → volume ready, container doesn't exist yet

→ SANDBOX PHASE:
  → kubelet → containerd: create pause container → CNI: pod gets IP
    → sandbox ready, app container doesn't exist yet

→ CONTAINER PHASE:
  → kubelet → containerd: create container from image
    → bind-mount: kubelet volume dir → container's /app/data
      → starts process → pod Running → app sees /app/data as normal dir

kubectl delete pod myapp
  → kubelet: SIGTERM → wait 30s → SIGKILL → remove container → remove sandbox
    → umount NFS (kernel: UMNT RPC → NAS releases handles)
      → rmdir kubelet volume dir → pod gone
        → PVC still Bound, PV still Bound, NAS data intact

kubectl delete pvc app-data
  → API server deletes PVC from etcd
    → PV controller: reclaimPolicy=Retain → PV status: Released
      → PV stuck in Released, no new PVC can bind
        → NAS: /shared/app-data still there, k8s can't touch it
          → admin must: SSH to NAS + rm -rf, then kubectl delete pv
            → or: kubectl edit pv → remove claimRef → Available again

node reboot recovery:
  → all mounts gone → kubelet starts → reads API: "pod myapp belongs here"
    → re-reads PV → re-mounts NFS → re-creates container → pod back
      → no fstab, kubelet reconciles from etcd every time
