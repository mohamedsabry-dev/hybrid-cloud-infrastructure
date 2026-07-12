NFS on Kubernetes — CSI Driver Lifecycle (Summary Trace)
=========================================================

CSI controller + CSI node pods already running in cluster.
StorageClass nfs-delete exists: provisioner=nfs.csi.k8s.io, server=10.0.40.120, share=/volume1/k8s-prod.

kubectl apply pvc.yaml (storageClassName: nfs-delete, requests: 10Gi)
  → API server stores PVC in etcd → status: Pending
    → CSI controller wakes up: "PVC references my StorageClass"
      → reads StorageClass parameters: server + share
        → mounts NFS on itself temporarily
          → mkdir /volume1/k8s-prod/pvc-d4f8a2b1-... on NAS
            → unmounts
              → creates PV in etcd (volumeHandle, subdir, claimRef)
                → PV and PVC both Bound — admin did nothing

kubectl apply pod.yaml (references PVC app-data)
  → API server stores pod → Pending
    → scheduler picks worker-01 → writes nodeName to etcd
      → kubelet on worker-01: "new pod, needs PVC app-data"
        → resolves: PVC → PV → CSI type → calls CSI node plugin via gRPC

→ VOLUME PHASE (CSI node does mount, not kubelet):
  → CSI node: NodePublishVolume(server, path, target, options)
    → mount -t nfs -o soft,timeo=10 10.0.40.120:/volume1/k8s-prod/pvc-d4f8a2b1-... → kubelet volume dir
      → kernel: RPC/XDR → TCP:2049 → IP → ARP → frame → VLAN 40 → switch → NAS
        → (identical to VM-level trace — see nfs-vm-read-trace.md)
          → returns success to kubelet via gRPC

→ SANDBOX PHASE:
  → kubelet → containerd: create pause container → CNI: pod gets IP

→ CONTAINER PHASE:
  → kubelet → containerd: create container from image
    → bind-mount: CSI volume dir → container's /app/data
      → starts process → pod Running

kubectl delete pod myapp
  → kubelet: SIGTERM → wait → SIGKILL → remove container → remove sandbox
    → calls CSI node via gRPC: NodeUnpublishVolume → umount
      → pod gone. PVC/PV still Bound. NAS folder intact.

kubectl delete pvc app-data (HERE is the difference from raw PV)
  → API server deletes PVC from etcd
    → PV controller: reclaimPolicy=Delete → triggers CSI deletion
      → CSI controller: reads PV volumeAttributes (server, share, subdir)
        → mounts NFS on itself temporarily
          → rm -rf /volume1/k8s-prod/pvc-d4f8a2b1-... on NAS
            → unmounts
              → deletes PV from etcd
                → everything gone: no PVC, no PV, no folder on NAS
