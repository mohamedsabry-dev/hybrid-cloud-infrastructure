# Issue: CoreDNS Not Highly Available - Should Run on Masters

**Status:** RESOLVED
**Date Discovered:** 2026-04-18
**Severity:** CRITICAL
**Discovered During:** DR Test 2 - Total Worker Loss

---

## Summary

CoreDNS pods (replicas=2) can both be scheduled on nodes that fail together, causing complete DNS failure. This breaks the entire cluster including self-healing systems.

---

## Problem

CoreDNS is deployed by kubeadm with replicas=2, but no nodeSelector forces it onto control-plane nodes. Both pods can end up on workers or a mix of workers and masters.

**During DR test:**
- coredns-m7bw6 → worker1 (SHUTDOWN)
- coredns-t8p4b → master3 (SHUTDOWN)
- **Result:** Complete DNS failure

---

## Impact

When DNS fails, everything fails:

```
DNS down
    ↓
kube-controller-manager can't do leader election
    ↓
No leader = no taint management
    ↓
Pods don't get evicted
    ↓
Remediation can't start (Vault DNS lookup fails)
    ↓
No self-healing
    ↓
CLUSTER STUCK
```

---

## Evidence

### Cascade Failure During DR Test

```
error authenticating: "Put \"https://vault.lab.local:8200/v1/auth/kubernetes/login\":
dial tcp: lookup vault.lab.local on 10.96.0.10:53: read: connection refused"
```

### kube-controller-manager Errors

```
E0418 19:44:19 "Error retrieving lease lock" err="context deadline exceeded"
```

Controller-manager couldn't maintain leadership because DNS was down.

---

## Solution Applied

Force CoreDNS to run on control-plane nodes only with podAntiAffinity to spread across masters.

### Command Applied (2026-04-18):

```bash
kubectl patch deployment coredns -n kube-system --type='strategic' -p '{
  "spec":{
    "template":{
      "spec":{
        "nodeSelector":{"node-role.kubernetes.io/control-plane":""},
        "tolerations":[{"key":"node-role.kubernetes.io/control-plane","operator":"Exists","effect":"NoSchedule"}],
        "affinity":{
          "podAntiAffinity":{
            "requiredDuringSchedulingIgnoredDuringExecution":[{
              "labelSelector":{"matchLabels":{"k8s-app":"kube-dns"}},
              "topologyKey":"kubernetes.io/hostname"
            }]
          }
        }
      }
    }
  }
}'
```

### Verified Result:

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
```
```
NAME                       READY   STATUS    NODE
coredns-74b76c898f-94k7p   1/1     Running   k8s-master2.lab.local
coredns-74b76c898f-rr6s9   1/1     Running   k8s-master3.lab.local
```

Both CoreDNS pods on different masters. Workers can all die, DNS stays up.

### Manual Operations Reference

Command recorded in: `kubernetes/docs/manual-operation.txt`

---

## Why Not Flux?

CoreDNS is managed by kubeadm, not Flux. Using Flux to patch it creates risk:

1. Flux needs API server → needs DNS → needs CoreDNS
2. If CoreDNS update fails mid-way, Flux can't recover
3. Circular dependency

**Recommended approach:** Apply via Ansible playbook during cluster setup/upgrades.

---

## Ansible Playbook

```yaml
# ansible/dev/playbooks/k8s/coredns_ha.yml
- name: Configure CoreDNS HA
  hosts: k8s_masters[0]
  gather_facts: false
  tasks:
    - name: Patch CoreDNS to run on masters
      shell: |
        kubectl patch deployment coredns -n kube-system --type='strategic' -p '{
          "spec": {
            "template": {
              "spec": {
                "nodeSelector": {
                  "node-role.kubernetes.io/control-plane": ""
                },
                "tolerations": [
                  {"key": "node-role.kubernetes.io/control-plane", "operator": "Exists", "effect": "NoSchedule"}
                ]
              }
            }
          }
        }'
      environment:
        KUBECONFIG: /etc/kubernetes/admin.conf
```

---

## Verification

After applying:

```bash
# Check pods are on masters
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide

# Test DNS works
kubectl run test-dns --rm -it --restart=Never --image=busybox -- nslookup kubernetes.default
```

---

## When to Re-Apply

- After `kubeadm upgrade` (may reset CoreDNS config)
- After cluster rebuild
- If CoreDNS deployment is recreated

---

## Related

- `disaster-recovery/tmp-partial-worker-loss.md` - DR Test where issue was discovered
- `troubleshooting/kubernetes/43-noexecute-taint-not-applied.md` - Related eviction issue (may be caused by DNS failure)

---

## Timeline

| Time | Event |
|------|-------|
| 2026-04-18 20:25 | DR Test 2 started |
| 2026-04-18 20:35 | DNS failure discovered |
| 2026-04-18 21:00 | Identified both CoreDNS on down nodes |
| 2026-04-18 21:30 | Manual start of master3 for DNS |
| 2026-04-18 22:20 | Confirmed DNS works with 1 CoreDNS on master1 |
| 2026-04-18 22:45 | Solution identified |
| 2026-04-18 ~23:45 | Fix applied with podAntiAffinity |
| 2026-04-18 ~23:45 | Verified: CoreDNS on master2 + master3 |
| 2026-04-18 | **RESOLVED** |
