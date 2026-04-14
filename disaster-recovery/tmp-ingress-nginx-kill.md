# Ingress NGINX Pod Kill
# Date: -
# Result: NOT TESTED

---

## Scope

Test ingress-nginx resilience under partial and full pod failure.

---

## Test A: Partial Failure (1 of 3 pods)

**Steps:**
1. Delete 1 ingress-nginx pod
2. Check: App still reachable via remaining 2 pods
3. Check: Traffic distribution shifts to surviving pods
4. Check: Killed pod restarts automatically

**Commands:**
```bash
# Get pods
kubectl get pods -n ingress-nginx

# Kill one pod
kubectl delete pod -n ingress-nginx <pod-name>

# Watch recovery
kubectl get pods -n ingress-nginx -w

# Test access
curl -I http://wordpress-dev.lab.local
```

---

## Test B: Full Failure (3 of 3 pods)

**Steps:**
1. Delete all 3 ingress-nginx pods
2. Check: App down (expected)
3. Check: Flux reconciliation kicks in
4. Measure: Time until all 3 pods restored
5. Check: App accessible after recovery

**Commands:**
```bash
# Kill all pods
kubectl delete pod -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx

# Watch recovery
kubectl get pods -n ingress-nginx -w

# Check Flux
flux get kustomization
```

---

## Expected Behavior

| Scenario | App Status | Recovery |
|----------|------------|----------|
| 1/3 down | UP | Auto (seconds) |
| 3/3 down | DOWN | Auto via Flux (~30s) |

---

## TODO

- [ ] Execute Test A
- [ ] Execute Test B
- [ ] Document recovery times
