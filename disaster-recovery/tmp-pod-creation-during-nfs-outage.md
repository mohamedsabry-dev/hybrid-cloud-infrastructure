# Pod Creation During NFS Outage
# Date: -
# Result: NOT TESTED

---

## Scope

During NAS outage, attempt to deploy a new app that requires NFS PVC.

---

## Steps

1. With NAS down, create new deployment requiring NFS PVC
2. Check: PVC stays Pending with clear error message
3. Check: Pod stays in Pending/FailedScheduling
4. Recovery: NAS back → PVC binds → pod starts

---

## Commands

```bash
# During NAS outage, create test PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-nfs-outage
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: nfs-retain
  resources:
    requests:
      storage: 1Gi
EOF

# Check PVC status
kubectl get pvc test-nfs-outage
kubectl describe pvc test-nfs-outage

# Create pod using PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-nfs-pod
  namespace: default
spec:
  containers:
  - name: test
    image: nginx
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: test-nfs-outage
EOF

# Check pod status
kubectl get pod test-nfs-pod
kubectl describe pod test-nfs-pod

# Cleanup after test
kubectl delete pod test-nfs-pod
kubectl delete pvc test-nfs-outage
```

---

## Expected Behavior

- PVC: Pending with provisioning error
- Pod: Pending (waiting for PVC)
- Error message: Clear indication of NFS failure
- After NAS up: Auto-recovers

---

## TODO

- [ ] Execute during NAS outage test
- [ ] Verify clear error messages
- [ ] Confirm auto-recovery
