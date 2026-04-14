# Full NAS Shutdown
# Date: -
# Result: NOT TESTED

---

## Scope

Power off NAS completely. Most realistic major disaster scenario.

---

## Steps

1. Power off NAS via Proxmox or NAS admin UI
2. Monitor all NFS-dependent pods simultaneously
3. Check: soft mount pods → CrashLoopBackOff
4. Check: hard mount pods → hang indefinitely
5. Check: Non-NFS components survive (Ingress, Vault, Flux)
6. Recovery: Power NAS back on
7. Verify recovery sequence

---

## Commands

```bash
# Check baseline
showmount -e 10.0.40.120

# Power off NAS (via Proxmox or NAS UI)
# ...

# Monitor pods
kubectl get pods -A -w

# Check non-NFS components
kubectl get pods -n ingress-nginx
kubectl get pods -n vault
flux get kustomization

# After NAS restored
showmount -e 10.0.40.120

# Check for stale mounts on workers
ssh root@k8s-worker1 'dmesg | grep nfs | tail -20'
```

---

## Expected Behavior

| Component | Behavior |
|-----------|----------|
| WordPress | CrashLoopBackOff (~9s) |
| MariaDB | Hangs (hard mount) |
| Prometheus/Grafana/Loki | Storage errors |
| Ingress-nginx | UP |
| Vault | UP |
| Flux | UP |
| etcd backup | Fails if mid-run |

---

## Recovery Sequence

1. Verify NAS exports available: `showmount -e 10.0.40.120`
2. Check which pods recovered automatically vs stuck
3. Check for stale NFS mounts on worker nodes
4. Restart CSI node pods if stale mounts detected
5. Delete and restart pods in CrashLoopBackOff
6. Verify MariaDB resumed and data intact
7. Verify WordPress accessible and media loading
8. Run etcd backup manually to confirm

---

## TODO

- [ ] Execute test (maintenance window)
- [ ] Document pod recovery times
- [ ] Check for stale mounts
- [ ] Verify data integrity after recovery
