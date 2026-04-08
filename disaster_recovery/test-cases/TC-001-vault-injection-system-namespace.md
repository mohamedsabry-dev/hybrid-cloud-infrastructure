# TC-001: Vault Injection Fails in System Namespaces

## Summary
Vault webhook denies secret injection into `kube-system` namespace, preventing pod creation.

## Error
```
Warning  FailedCreate  replicaset-controller  Error creating: admission webhook "vault.hashicorp.com" denied the request: error with request namespace: cannot inject into system namespaces: kube-system
```

## Symptoms
- Deployment shows `0/1` ready, `UP-TO-DATE: 0`
- ReplicaSet exists but no pods created
- No pods visible with label selector

## Diagnostic Commands

### 1. Check Deployment Status
```bash
kubectl get deployment remediation -n kube-system
```
**Output:**
```
NAME          READY   UP-TO-DATE   AVAILABLE   AGE
remediation   0/1     0            0           13m
```

### 2. Check ReplicaSet
```bash
kubectl get rs -n kube-system | grep remediation
```
**Output:**
```
remediation-69dd7f9887   1   0   0   13m
```

### 3. Check Pods
```bash
kubectl get pods -n kube-system -l app=remediation
```
**Output:**
```
No resources found in kube-system namespace.
```

### 4. Describe ReplicaSet for Events
```bash
kubectl describe rs remediation-69dd7f9887 -n kube-system
```
**Output (Events):**
```
Warning  FailedCreate  replicaset-controller  Error creating: admission webhook "vault.hashicorp.com" denied the request: error with request namespace: cannot inject into system namespaces: kube-system
```

## Root Cause
Vault's admission webhook is configured by default to deny injection into Kubernetes system namespaces (`kube-system`, `kube-public`, `kube-node-lease`) for security reasons.

## Solution
Move the deployment to a dedicated non-system namespace.

### 1. Create Namespace YAML
```yaml
# namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: remediation
```

### 2. Update All Manifests
Change `namespace: kube-system` to `namespace: remediation` in:
- configmap.yaml
- deployment.yaml
- remediation-auth-sa.yaml
- vault-ca-secret.yaml

### 3. Update Kustomization
Add `namespace.yaml` to resources in `kustomization.yaml`:
```yaml
resources:
  - namespace.yaml
  - configmap.yaml
  - deployment.yaml
  - remediation-auth-sa.yaml
  - priorityclass.yaml
  - vault-ca-secret.yaml
```

### 4. Update Vault Role
```bash
vault write auth/kubernetes/role/remediation \
  bound_service_account_names=remediation-sa \
  bound_service_account_namespaces=remediation \
  policies=remediation-policy \
  ttl=1h
```

### 5. Verify Vault Role
```bash
vault read auth/kubernetes/role/remediation
```

### 6. Deploy and Reconcile
```bash
git add -A && git commit -m "Move remediation to dedicated namespace" && git push origin dev
flux reconcile kustomization deployments --with-source
```

### 7. Verify Deployment
```bash
kubectl get pods -n remediation
kubectl logs -n remediation -l app=remediation
```

## Prevention
- Always use dedicated namespaces for workloads requiring Vault injection
- Avoid deploying Vault-injected pods to system namespaces
- Document namespace requirements in deployment guides

## Related
- Vault Agent Injector documentation
- Kubernetes namespace best practices
