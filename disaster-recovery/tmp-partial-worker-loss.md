# Partial Worker Loss (2 of 3)
# Date: -
# Result: NOT TESTED

---

## Scope

Force shutdown 2 of 3 workers. Test cluster behavior under severe worker loss.

---

## Steps

1. Force shutdown 2 worker nodes
2. Check: Remaining worker handles all pods?
3. Check: Resource pressure on surviving worker
4. Check: Any pods stuck in Pending (insufficient resources)?
5. Recovery: Start workers → pods redistribute

---

## Commands

```bash
# Force shutdown 2 workers via Proxmox
# qm stop <worker1-vmid> --skiplock
# qm stop <worker2-vmid> --skiplock

# Watch cluster state
kubectl get nodes -w
kubectl get pods -A -o wide

# Check resource pressure
kubectl top nodes
kubectl describe node k8s-worker3 | grep -A 10 "Allocated resources"
```

---

## Expected Behavior

- 1 worker handles critical pods (WordPress, MariaDB)
- Some pods may be Pending if resources insufficient
- Recovery when workers return

---

## TODO

- [ ] Execute test
- [ ] Document resource pressure
- [ ] Identify pods that don't fit on 1 worker
