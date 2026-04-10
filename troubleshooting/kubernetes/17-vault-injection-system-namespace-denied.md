# TS-K8S-017 | 2026-04-07 | RESOLVED

## 1. Context
- System: Vault Agent Injector / Kubernetes Admission Webhook
- Environment: DEV (k8s cluster)
- Related components: Remediation pod deployment, Vault webhook, kube-system namespace
- Discovered during: DR self-healing pod deployment

## 2. Issue
- Symptom: Deployment shows `0/1` ready, no pods created despite ReplicaSet existing
- Error:
```
Warning  FailedCreate  replicaset-controller  Error creating: admission webhook "vault.hashicorp.com" denied the request: error with request namespace: cannot inject into system namespaces: kube-system
```

## 3. Analysis

**Check 1: Deployment Status**
```bash
kubectl get deployment remediation -n kube-system
```
```
NAME          READY   UP-TO-DATE   AVAILABLE   AGE
remediation   0/1     0            0           13m
```
Finding: UP-TO-DATE: 0 indicates no pods ever created successfully. ✓

---

**Check 2: ReplicaSet Status**
```bash
kubectl get rs -n kube-system | grep remediation
```
```
remediation-69dd7f9887   1   0   0   13m
```
Finding: ReplicaSet exists but DESIRED:1, CURRENT:0, READY:0 - pods never created. ✓

---

**Check 3: Pod Status**
```bash
kubectl get pods -n kube-system -l app=remediation
```
```
No resources found in kube-system namespace.
```
Finding: No pods exist - creation blocked before pod object created. ✓

---

**Check 4: ReplicaSet Events**
```bash
kubectl describe rs remediation-69dd7f9887 -n kube-system
```
```
Events:
  Warning  FailedCreate  replicaset-controller  Error creating: admission webhook "vault.hashicorp.com" denied the request: error with request namespace: cannot inject into system namespaces: kube-system
```
Finding: **Vault admission webhook actively blocking pod creation.** ✓

## 4. Root Cause
> Vault's admission webhook is configured by default to deny injection into Kubernetes system namespaces (`kube-system`, `kube-public`, `kube-node-lease`) for security reasons. This is intentional - system namespaces contain critical cluster components and injecting sidecars could destabilize them.

## 5. Solution
> Move the deployment to a dedicated non-system namespace.

**Step 1: Create Namespace**
```yaml
# namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: remediation
```

**Step 2: Update All Manifests**

Change `namespace: kube-system` to `namespace: remediation` in:
- configmap.yaml
- deployment.yaml
- remediation-auth-sa.yaml
- vault-ca-secret.yaml

**Step 3: Update Kustomization**
```yaml
resources:
  - namespace.yaml
  - configmap.yaml
  - deployment.yaml
  - remediation-auth-sa.yaml
  - priorityclass.yaml
  - vault-ca-secret.yaml
```

**Step 4: Update Vault Role**
```bash
vault write auth/kubernetes/role/remediation \
  bound_service_account_names=remediation-sa \
  bound_service_account_namespaces=remediation \
  policies=remediation-policy \
  ttl=1h
```

**Step 5: Verify Vault Role**
```bash
vault read auth/kubernetes/role/remediation
```

**Step 6: Deploy and Reconcile**
```bash
git add -A && git commit -m "Move remediation to dedicated namespace" && git push origin dev
flux reconcile kustomization deployments --with-source
```

## 6. Solution Risk
- Risk level: LOW
- Potential impact: Need to update any references to the old namespace

## 7. Impact After Fix
- Observed: Pod created successfully in `remediation` namespace
- Vault injection working

**Verification:**
```bash
kubectl get pods -n remediation
kubectl logs -n remediation -l app=remediation
```

## 8. Notes

**Why Vault blocks system namespaces:**
- System namespaces contain critical cluster components (API server, scheduler, etc.)
- Injecting sidecars could destabilize control plane
- Security boundary - system components shouldn't depend on user-deployed services

**Prevention:**
- Always use dedicated namespaces for workloads requiring Vault injection
- Avoid deploying Vault-injected pods to system namespaces
- Document namespace requirements in deployment guides

**System namespaces blocked by default:**
- `kube-system`
- `kube-public`
- `kube-node-lease`

## 9. Workaround (if any)
> Can configure Vault to allow system namespace injection (NOT recommended):
> ```yaml
> injector:
>   namespaceSelector:
>     matchExpressions:
>       - key: kubernetes.io/metadata.name
>         operator: NotIn
>         values: []  # Empty = allow all
> ```
> **Do not use this** - defeats the security purpose. Use dedicated namespace instead.

