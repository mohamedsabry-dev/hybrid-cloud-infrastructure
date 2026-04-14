# Partial Master Loss (2 of 3)
# Date: -
# Result: NOT TESTED

---

## Scope

Force shutdown 2 of 3 masters. Test etcd quorum loss and API server behavior.

---

## Steps

1. Force shutdown 2 master nodes
2. Check: etcd quorum LOST (only 1 of 3)
3. Check: API server behavior — read-only or unavailable?
4. Check: Existing pods still running (kubelet independent)
5. Recovery: Start 1 master → quorum restored

---

## Commands

```bash
# Force shutdown 2 masters via Proxmox
# qm stop <master1-vmid> --skiplock
# qm stop <master2-vmid> --skiplock

# Check API server (should fail or be read-only)
kubectl get nodes

# Check etcd on remaining master
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint status

# Existing pods still running (kubelet is independent)
ssh root@k8s-worker1 'crictl ps'
```

---

## Expected Behavior

- etcd quorum: LOST
- API server: Unavailable or read-only
- Existing pods: Still running (kubelet cached state)
- New scheduling: Blocked
- Recovery: Start 1 master → quorum restored → full functionality

---

## TODO

- [ ] Execute test
- [ ] Document API server behavior during quorum loss
- [ ] Verify existing pods survive
- [ ] Measure recovery time
