# DR Test Plan: NAS Storage Outage
# Environment: DEV cluster
# Date: TBD
# Tester: Sabry

---

## Objective

Validate cluster behavior and recovery across different levels of NAS storage outage.
Confirm which workloads survive, which fail gracefully, and which require manual intervention.

---

## Pre-Test Checklist

Before starting any scenario:

- [ ] All pods Running and healthy: `kubectl get pods -A`
- [ ] All PVCs Bound: `kubectl get pvc -A`
- [ ] No Released PVs: `kubectl get pv | grep Released`
- [ ] Flux healthy: `flux get kustomization`
- [ ] WordPress accessible: `curl -I https://wordpress-dev.lab.local`
- [ ] MariaDB healthy: `kubectl exec -it mariadb-0 -n database -c mariadb -- mariadb -u root -p -e "show databases;"`
- [ ] CSI controllers on workers: `kubectl get pods -n kube-system -o wide | grep csi-nfs-controller`
- [ ] etcd backup CronJob healthy: `kubectl get cronjob -n etcd-backup`
- [ ] Vault unsealed: `kubectl exec -it -n vault <vault-pod> -- vault status`
- [ ] Document baseline pod locations: `kubectl get pods -A -o wide`
- [ ] Document NAS disk usage before test

---

## Scenarios

---

### Scenario 1 — Single Worker NFS Interface Down

**Simulate:**
```bash
# Shutdown NFS network interface on worker1 only
# Node stays up, other workers unaffected
ssh root@k8s-worker1 'ip link set <nfs-interface> down'
```

**What to monitor:**
- Pods on worker1 with NFS mounts — hang or fail?
- WordPress (soft mount) — returns 500 or hangs?
- MariaDB if on worker1 (hard mount) — hangs and waits?
- Readiness probe — fails and removes pod from Service endpoints?
- Load balancer — routes traffic away from unhealthy pods?
- K8s — reschedules pods or keeps on same node?
- New PVC creation during outage — fails gracefully?
- csi-nfs-node on worker1 — how does it handle broken mount?

**Expected outcomes:**
- WordPress pods on worker1: readiness probe fails → removed from Service → other replicas serve
- MariaDB if on worker1: hangs (hard mount) → waits for NFS recovery
- Pods on worker2/worker3: unaffected ✅
- CSI controller if on worker1: provisioning degraded (1 replica still on worker2)
- New PVC: may succeed via controller on worker2

**Restore:**
```bash
ssh root@k8s-worker1 'ip link set <nfs-interface> up'
```

**Post-restore checks:**
- Do pods recover automatically or need restart?
- Are any mounts stale? (TS-K8S-015 pattern)
- MariaDB data integrity intact?

---

### Scenario 2 — Two Workers NFS Interface Down

**Simulate:**
```bash
ssh root@k8s-worker1 'ip link set <nfs-interface> down'
ssh root@k8s-worker2 'ip link set <nfs-interface> down'
```

**Additional checks vs Scenario 1:**
- WordPress 3 replicas: 2 down → 1 healthy → is site still up?
- CSI controller: both replicas may be on affected workers → provisioning blocked?
- MariaDB: if on worker1 or worker2 → how long before manual intervention needed?
- Ingress-nginx: still routing to healthy backend?

**Expected outcomes:**
- WordPress: 1 replica still serving if on worker3
- MariaDB: stuck if on affected worker, unaffected if on worker3
- CSI controller: degraded or fully blocked depending on placement

**Restore:**
```bash
ssh root@k8s-worker1 'ip link set <nfs-interface> up'
ssh root@k8s-worker2 'ip link set <nfs-interface> up'
```

---

### Scenario 3 — All 3 Workers NFS Interface Down

**Simulate:**
```bash
ssh root@k8s-worker1 'ip link set <nfs-interface> down'
ssh root@k8s-worker2 'ip link set <nfs-interface> down'
ssh root@k8s-worker3 'ip link set <nfs-interface> down'
```

**What to monitor:**
- All WordPress pods: soft mount → I/O errors → CrashLoopBackOff?
- MariaDB: hard mount → hangs → WordPress shows DB error
- CSI controller: both replicas affected → all provisioning blocked
- Ingress-nginx: no NFS dependency → still routing?
- Vault: no NFS dependency → still serving secrets?
- Flux: no NFS dependency → still reconciling?
- K8s: does it try to reschedule pods to masters? (should not — masters have no NFS)
- New pod creation: stays Pending if needs NFS?

**Expected outcomes:**
- WordPress: CrashLoopBackOff (soft mount I/O errors)
- MariaDB: hanging (hard mount) → database unavailable → WordPress shows DB error
- Ingress-nginx: up ✅
- Vault: up ✅
- Flux: up ✅
- New NFS PVC: stuck Pending

**Restore:**
```bash
ssh root@k8s-worker1 'ip link set <nfs-interface> up'
ssh root@k8s-worker2 'ip link set <nfs-interface> up'
ssh root@k8s-worker3 'ip link set <nfs-interface> up'
```

---

### Scenario 4 — Full NAS Shutdown (Complete Storage Loss)

**Most realistic major disaster scenario. Run last.**

**Simulate:**
Power off NAS via Proxmox or NAS admin UI.

**What to monitor:**
- All NFS-mounted pods simultaneously
- soft mount pods (WordPress, Prometheus, Grafana, Loki) → CrashLoopBackOff
- hard mount pods (MariaDB) → hang indefinitely
- CSI controller → cannot provision or delete any PVC
- etcd backup CronJob → if fires during outage → fails gracefully?
- Ingress-nginx → still routing? (no NFS dependency)
- Vault → still serving secrets? (no NFS dependency)
- Flux → still reconciling? (no NFS dependency)
- FreeIPA → does losing NAS affect DNS or identity services?
- Proxmox → does losing NAS affect any VM disk or config backup?
- Remediation pod → does it try to auto-heal and cause side effects?
- Linux kernel NFS messages on worker nodes

**Expected outcomes:**
- WordPress: CrashLoopBackOff within ~9 seconds (soft mount timeout)
- MariaDB: hanging → database unavailable
- Monitoring stack: Prometheus/Grafana/Loki storage errors
- Ingress-nginx: up ✅
- Vault: up ✅
- Flux: up ✅
- etcd backup: fails if mid-run, skips if not scheduled

**Restore:**
Power NAS back on, wait for NFS exports to come up.

**Post-restore recovery sequence:**
1. Verify NAS exports available: `showmount -e 10.0.40.120`
2. Check which pods recovered automatically vs stuck
3. Check for stale NFS mounts on worker nodes
4. Restart CSI node pods if stale mounts detected
5. Delete and restart pods in CrashLoopBackOff
6. Verify MariaDB resumed and data intact
7. Verify WordPress accessible and media loading
8. Verify Prometheus/Grafana/Loki recovered
9. Run etcd backup manually to confirm it works post-recovery

---

### Scenario 5 — Full NAS Shutdown + New Pod Creation During Outage

**Extension of Scenario 4.**

While NAS is down, attempt to deploy a new app that requires NFS PVC.

**What to check:**
- Does PVC stay Pending with clear error message?
- Does pod stay in Pending/FailedScheduling?
- Does it recover automatically when NAS comes back?
- Does the error message clearly indicate NFS provisioning failure?

---

### Scenario 6 — Full NAS Shutdown + etcd Backup During Outage

**Extension of Scenario 4.**

While NAS is down, trigger the etcd backup CronJob manually:
```bash
kubectl create job --from=cronjob/etcd-backup etcd-backup-dr-test -n etcd-backup
```

**What to check:**
- Does the job fail gracefully or hang?
- Does it return a clear error?
- Does vault-agent-init still authenticate successfully? (no NFS dependency)
- Does the backup fail at the NFS write step or earlier?
- Does the job clean up correctly after failure?

---

## Linux NFS Debug Commands (Run on Affected Worker Nodes)

```bash
# Check mounted NFS paths
mount | grep nfs

# Check if worker can see NAS exports
showmount -e 10.0.40.120

# Kernel NFS messages
dmesg | grep -i nfs | tail -20

# NFS mount statistics
nfsstat -m

# Test if a mount is stale (will hang if stale — use timeout)
timeout 5 ls /var/lib/kubelet/pods/

# Check kernel mount table
cat /proc/mounts | grep nfs

# Check NFS-related errors in system logs
journalctl -u kubelet | grep -i nfs | tail -20
```

---

## Components That Should Survive Any NAS Outage

These have no NFS dependency and must remain up throughout all scenarios:

| Component | Reason |
|---|---|
| ingress-nginx | No NFS storage |
| Vault | Runs on LXC with local Raft storage |
| Flux controllers | No NFS storage |
| FreeIPA | Runs on LXC with local storage |
| CoreDNS | No NFS storage |
| Calico CNI | No NFS storage |
| etcd | Local disk on masters |
| Kubernetes API server | Local disk on masters |

---

## Components That Will Be Affected

| Component | Mount Type | Expected Behavior |
|---|---|---|
| WordPress | soft | CrashLoopBackOff after ~9s |
| MariaDB | hard | Hangs indefinitely, recovers when NAS returns |
| Prometheus | soft | Storage errors, may CrashLoopBackOff |
| Grafana | soft | Storage errors |
| Loki | soft | Storage errors |
| Alertmanager | soft | Storage errors |
| etcd backup | soft | Fails if NAS down during backup |
| Remediation | soft | Check behavior — may try to auto-heal |

---

## Recovery Priority Order (After NAS Restored)

```
1. Verify NAS exports available
2. Check and clear stale NFS mounts on worker nodes
3. MariaDB — confirm resumed or restart pod
4. Verify MariaDB data integrity
5. WordPress — restart if CrashLoopBackOff
6. Verify WordPress accessible + media loading
7. Prometheus/Grafana/Loki — restart if needed
8. Run etcd backup manually — confirm works post-recovery
9. Check all PVCs still Bound
10. Check for any new Released PVs created during outage
```