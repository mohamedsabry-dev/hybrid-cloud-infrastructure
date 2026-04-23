# Graceful Power Down (UPS Triggered)
# Date: -
# Result: NOT TESTED

---

## Scope

Simulate electricity loss triggering UPS shutdown script. Document correct order.

---

## Shutdown Order

1. App pods (drain workers)
2. K8s workers
3. K8s masters
4. Vault LXCs
5. Proxmox host

---

## Steps

1. Trigger UPS shutdown script (or simulate manually)
2. Verify shutdown order executes correctly
3. Verify each component shuts down cleanly
4. Verify no data corruption

---

## Commands

```bash
# Manual simulation of graceful shutdown:

# 1. Drain workers (evict pods gracefully)
kubectl drain k8s-worker1 --ignore-daemonsets --delete-emptydir-data
kubectl drain k8s-worker2 --ignore-daemonsets --delete-emptydir-data
kubectl drain k8s-worker3 --ignore-daemonsets --delete-emptydir-data

# 2. Shutdown workers
ssh root@k8s-worker1 'shutdown -h now'
ssh root@k8s-worker2 'shutdown -h now'
ssh root@k8s-worker3 'shutdown -h now'

# 3. Shutdown masters (one at a time, maintain quorum until last)
ssh root@k8s-master1 'shutdown -h now'
ssh root@k8s-master2 'shutdown -h now'
ssh root@k8s-master3 'shutdown -h now'

# 4. Shutdown Vault LXCs
ssh root@vault1 'shutdown -h now'
ssh root@vault2 'shutdown -h now'
ssh root@vault3 'shutdown -h now'

# 5. Shutdown Proxmox (last)
# shutdown -h now
```

---

## Expected Behavior

- Each component shuts down cleanly
- No data corruption
- Logs show graceful termination
- etcd snapshot clean before master shutdown

---

## TODO

- [ ] Create UPS shutdown script
- [ ] Test manual shutdown sequence
- [ ] Verify no data corruption
- [ ] Document in runbook
