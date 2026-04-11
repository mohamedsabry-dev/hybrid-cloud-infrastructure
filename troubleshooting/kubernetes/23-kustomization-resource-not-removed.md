# TS-K8S-023 | 2026-04-11 | RESOLVED

## 1. Context
- System: Flux GitOps, Kustomization resources
- Environment: Production cluster (prod)
- Related components: testing namespace, ingress-test deployment, kustomization.yaml

## 2. Issue
- Symptom: Test pod `ingress-test` running in production when it should have been excluded from deployment.
- Error:
```bash
kubectl get pods -n testing
NAME                           READY   STATUS    RESTARTS   AGE
ingress-test-5bbc69f45-xv8cl   1/1     Running   2          42h
```

**Impact:** Low - test workload consuming resources in prod, but no functional impact.

## 3. Analysis

### Discovery

While investigating worker2 failure, noticed test pod running:
```bash
kubectl get pods -A -o wide | grep testing
testing   ingress-test-5bbc69f45-xv8cl   1/1   Running   k8s-worker3.lab.local
```

### Investigation

Checked kustomization file:
```bash
cat kubernetes/prod/deployments/apps/testing/kustomization.yaml
```

Found:
```yaml
resources:
  - ingress-test  # Should have been commented out!
```

### Root Cause

User forgot to comment out the ingress-test resource from kustomization.yaml after testing was complete. Flux continued deploying the test workload.

## 4. Root Cause
> Human error - forgot to remove/comment test resource from kustomization.yaml after testing completed.

## 5. Solution
> Comment out or remove the test resource from kustomization.yaml.

```yaml
# Before
resources:
  - ingress-test

# After
resources:
  # - ingress-test  # Disabled - testing complete
```

Then either:
- Wait for Flux to reconcile and remove the resource
- Or manually delete: `kubectl delete deployment ingress-test -n testing`

## 6. Solution Risk
- Risk level: LOW
- Potential impact: None - removing test workload

## 7. Impact After Fix
- Observed: Test pod removed from cluster
- Resources freed

## 8. Notes

### Prevention

**Option 1: Use separate test kustomization**
```
kubernetes/prod/deployments/apps/
├── kustomization.yaml      # Production apps only
└── testing/
    └── kustomization.yaml  # Test apps - not referenced by parent
```

**Option 2: Use Flux suspend**
```bash
# Suspend test kustomization instead of commenting
flux suspend kustomization testing
```

**Option 3: Environment-based includes**
```yaml
# Only include testing in dev
resources:
  - wordpress
  - mariadb
  # Testing only in dev via overlay
```

### Lesson Learned

Test resources should either:
1. Live in separate kustomization not auto-deployed
2. Be in dev environment only
3. Have clear naming convention (prefix: `test-`, `debug-`)
4. Be cleaned up immediately after testing

## 9. Workaround (if any)
> Quick cleanup: `kubectl delete deployment ingress-test -n testing`
