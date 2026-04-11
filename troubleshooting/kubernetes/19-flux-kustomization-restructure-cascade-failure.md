# TS-K8S-019 | 2026-04-09 | RESOLVED

> **REAL INCIDENT** — This case occurred during an unplanned production failure (power outage recovery + Flux restructuring cascade), not planned DR testing. Documented before DR test phase began.

## 1. Context
- System: Flux CD / Kubernetes / Vault Agent Injector
- Environment: DEV (k8s cluster)
- Related components: Flux Kustomizations, HelmReleases, Vault, WordPress, MariaDB, Ingress-NGINX
- Discovered during: Real power outage recovery (unplanned incident)

## 2. Issue
- Symptom: Multiple cascading failures after power outage and subsequent Flux restructuring
- Impact: Complete cluster outage - all applications down
- Severity: **CATASTROPHIC**

**Issue Chain:**
1. WordPress DB connection failure (vault-agent sidecar missing)
2. Remediation pod CrashLoopBackOff (same root cause)
3. Flux prune deleted ALL HelmReleases causing complete outage

## 3. Analysis

### Phase 1: WordPress Database Connection Failure (12:54 PM)

**Check 1: Initial Symptoms**
```
Warning: mysqli_real_connect(): (HY000/1045): Access denied for user 'wordpress'@'10.245.62.24' (using password: YES)
Error establishing a database connection
```

**Check 2: Pod Status Comparison**
```bash
[root@k8s-master1 ~]# kubectl get pods -n database
NAME        READY   STATUS    RESTARTS   AGE
mariadb-0   2/2     Running   0          12m    # Has vault-agent sidecar

[root@k8s-master1 ~]# kubectl get pods -n apps
NAME                         READY   STATUS    RESTARTS   AGE
wordpress-85b7f46448-k6qlw   1/1     Running   0          4h5m   # MISSING sidecar!
```
Finding: MariaDB has 2/2 (vault-agent present), WordPress has 1/1 (missing).

---

**Check 3: Vault Secrets Directory**
```bash
[root@k8s-master1 ~]# kubectl exec -it deploy/wordpress -n apps -- bash
root@wordpress-85b7f46448-rwxx9:/# ls -la /vault/secrets/
ls: cannot access '/vault/secrets/': No such file or directory
```
Finding: `/vault/secrets/` directory missing - injection never happened.

---

**Check 4: Compare Annotations**
```bash
# MariaDB (working)
kubectl get pod mariadb-0 -n database -o jsonpath='{.metadata.annotations}' | jq . | grep vault
  "vault.hashicorp.com/agent-inject-status": "injected",   # KEY!

# WordPress (not working)
kubectl get pod -n apps -l app=wordpress -o jsonpath='{.items[0].metadata.annotations}' | jq . | grep vault
  # MISSING: "vault.hashicorp.com/agent-inject-status": "injected"
```
Finding: WordPress pods missing `agent-inject-status: injected` annotation.

---

**Check 5: etcd Backup Comparison (10:40 AM - before outage)**
```bash
ETCDCTL_API=3 etcdctl --endpoints=http://127.0.0.1:2399 get /registry/pods/apps --prefix --keys-only | grep wordpress
/registry/pods/apps/wordpress-85b7f46448-cx2ct   # Different pods!

ETCDCTL_API=3 etcdctl ... | strings | grep -i "vault-agent"
vault-agent        # OLD pods HAD the sidecar!
vault-agent-init
```
Finding: Old pods (before outage) had vault-agent. Current pods do not. Deployment rollout happened during recovery.

---

**Check 6: Timestamp Analysis**
```
| Time     | Event                                            |
|----------|--------------------------------------------------|
| 09:00 AM | WordPress pods created (injector NOT ready)      |
| 11:00 AM | Power outage                                     |
| 12:14 PM | Vault Injector starts and becomes ready          |
| 12:52 PM | MariaDB pod recreated (injector now ready) 2/2   |
| 12:54 PM | WordPress containers restart (same old pods) 1/1 |
```
Finding: WordPress pods created BEFORE Vault Injector was ready.

---

### Phase 1 Root Cause

Flux Kustomization applies BOTH infrastructure and apps simultaneously with NO dependency ordering:

```yaml
# kubernetes/dev/flux/deployments-sync.yaml
path: ./kubernetes/dev/deployments    # Applies everything at once

# kubernetes/dev/deployments/kustomization.yaml
resources:
  - infrastructure   # vault-agent-injector here
  - apps             # wordpress here - NO DEPENDENCY!
```

**Sequence during cluster recovery:**
1. Flux applies ALL manifests simultaneously
2. Vault HelmRelease triggers -> Injector pod starts spinning up
3. WordPress Deployment triggers -> NEW pods created IMMEDIATELY
4. But Vault Injector isn't READY yet -> pods created WITHOUT sidecar
5. WordPress pods come up as 1/1 (no vault-agent) -> can't get DB password

---

### Phase 2: Remediation Pod CrashLoopBackOff (14:00 PM)

After splitting Flux into infrastructure-sync + apps-sync:

```bash
[root@k8s-master1 ~]# kubectl get pods -n remediation
NAME                           READY   STATUS             RESTARTS      AGE
remediation-56bdddfcd7-4vjhx   0/1     CrashLoopBackOff   5 (2m36s ago) 7m47s

[root@k8s-master1 ~]# kubectl logs remediation-56bdddfcd7-4vjhx -n remediation
FileNotFoundError: [Errno 2] No such file or directory: '/vault/secrets/proxmox-creds'
```

**Root Cause:** Remediation was in `infrastructure/` folder alongside `vault/`:
```
kubernetes/dev/deployments/infrastructure/
  ├── vault/          # vault-agent-injector
  ├── remediation/    # ALSO here - deploys SAME TIME as vault!
```

**Fix:** Moved remediation from `infrastructure/` to `apps/` folder.

---

### Phase 3: Vault Authentication Failure (14:09 PM)

```bash
[root@k8s-master1 ~]# kubectl get pods -A | grep -E "Init|vault"
apps         wordpress-6d5cdf8c64-rbk6q   0/2   Init:0/2   0   27m
database     mariadb-0                    0/2   Init:0/1   0   27m
monitoring   kube-prometheus-stack-grafana-*   0/4   Init:1/2   0   2m
```

**vault-agent-init logs:**
```
2026-04-09T14:09:53.975Z [ERROR] agent.auth.handler: error authenticating:
  error=
  | URL: PUT https://vault.lab.local:8200/v1/auth/kubernetes/login
  | Code: 403. Errors:
  | * permission denied
```

**Check: vault-auth secret**
```bash
[root@k8s-master1 ~]# kubectl get secret -n vault vault-auth -o jsonpath='{.data.token}' | base64 -d
Error from server (NotFound): secrets "vault-auth" not found

[root@k8s-master1 ~]# kubectl get sa vault-auth -n kube-system
NAME         AGE
vault-auth   18m

[root@k8s-master1 ~]# kubectl get secret -n kube-system | grep vault-auth
# Empty - no token secret!
```

**Root Cause:** Chain of events from Flux Kustomization rename:
1. Renamed Flux Kustomization from `deployments` -> `infrastructure` + `apps`
2. Flux `prune: true` deleted all resources from old `deployments` Kustomization
3. vault-auth-token secret was deleted
4. K8s 1.24+ doesn't auto-create SA token secrets
5. Vault can't validate any pod authentication
6. All pods with vault injection stuck

---

### Phase 4: COMPLETE CLUSTER OUTAGE (15:00 PM)

**Timeline of Disaster:**
```
15:00:35 - Flux infrastructure kustomization starts reconciling
15:00:37 - Flux UNINSTALLS vault HelmRelease ("uninstalled Helm release for deleted resource")
15:00:37 - vault-agent-injector DELETED
15:00:37 - All HelmReleases DELETED (vault, ingress-nginx, csi-driver-nfs)
15:00:xx - infrastructure stuck in "Reconciliation in progress"
           (healthCheck waiting for vault-agent-injector that no longer exists)
15:00:xx - apps stuck waiting for infrastructure
15:00:xx - ALL PODS with vault injection stuck in Init:0/2
15:00:xx - ingress-nginx down - no external access
```

**Evidence:**
```bash
[root@k8s-master1 tmp]# flux logs --kind=HelmRelease --name=vault -n vault
2026-04-09T15:00:37.206Z info HelmRelease/vault.vault - uninstalled Helm release for deleted resource

[root@k8s-master1 tmp]# kubectl get helmrelease -A
No resources found

[root@k8s-master1 tmp]# kubectl get pods -n vault
No resources found in vault namespace.
```

**The Chicken-and-Egg Problem:**
```
infrastructure-sync.yaml has:
  healthChecks:
    - kind: Deployment
      name: vault-agent-injector  <- Waiting for this
      namespace: vault

But vault-agent-injector was DELETED by prune!

1. Infrastructure waits for vault-agent-injector to be healthy
2. But vault-agent-injector doesn't exist (HelmRelease was pruned)
3. Infrastructure never completes
4. Apps waits for infrastructure
5. Nothing deploys
6. COMPLETE OUTAGE
```

## 4. Root Cause

> Multiple compounding failures:
> 1. **No Flux dependency ordering** - Apps deployed before Vault Injector ready
> 2. **Flux prune behavior** - Renaming Kustomization triggered mass deletion
> 3. **K8s 1.24+ SA tokens** - ServiceAccount tokens not auto-created
> 4. **HealthCheck deadlock** - Waiting for deleted resource

## 5. Solution

### Immediate Recovery Steps

**Step 1: Suspend infrastructure to break deadlock**
```bash
flux suspend kustomization infrastructure
```

**Step 2: Manually bootstrap vault HelmRelease**
```bash
kubectl apply -f - <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: hashicorp
  namespace: vault
spec:
  interval: 5m
  url: https://helm.releases.hashicorp.com
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: vault
  namespace: vault
spec:
  interval: 5m
  chart:
    spec:
      chart: vault
      version: "0.32.0"
      sourceRef:
        kind: HelmRepository
        name: hashicorp
        namespace: vault
  values:
    global:
      externalVaultAddr: "https://vault.lab.local:8200"
    server:
      enabled: false
    injector:
      enabled: true
      priorityClassName: system-cluster-critical
EOF
```

**Step 3: Create vault-auth token secret**
```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: vault-auth-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: vault-auth
type: kubernetes.io/service-account-token
EOF
```

**Step 4: Update Vault trust**
```bash
cd ansible/dev
ansible-playbook playbooks/k8s/integration-vault-k8s-trust.yml
```

**Step 5: Resume and reconcile**
```bash
flux resume kustomization infrastructure
flux reconcile kustomization infrastructure --with-source
flux reconcile kustomization apps
```

**Step 6: Delete stuck pods**
```bash
kubectl delete pod -n apps -l app=wordpress
kubectl delete pod -n database mariadb-0
kubectl delete pod -n monitoring -l app.kubernetes.io/name=grafana
kubectl delete pod -n remediation -l app=remediation
```

### Permanent Fixes Applied

**1. Split Flux Kustomizations with dependencies:**
- `kubernetes/dev/flux/infrastructure-sync.yaml` - healthCheck on vault-agent-injector
- `kubernetes/dev/flux/apps-sync.yaml` - dependsOn: infrastructure

**2. Move remediation to apps folder:**
```bash
git mv kubernetes/dev/deployments/infrastructure/remediation kubernetes/dev/deployments/apps/
```

**3. Add token secret to vault-auth manifest (K8s 1.24+ compatible):**
```yaml
# kubernetes/dev/deployments/infrastructure/vault/vault-auth-sa.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-auth
  namespace: kube-system
---
apiVersion: v1
kind: Secret
metadata:
  name: vault-auth-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: vault-auth
type: kubernetes.io/service-account-token
```

## 6. Solution Risk
- Risk level: HIGH (for the restructuring)
- Potential impact: Already experienced - complete cluster outage

## 7. Impact After Fix
```bash
[root@k8s-master1 tmp]# flux get kustomization
NAME            REVISION                READY   MESSAGE
apps            prod@sha1:23a0d468      True    Applied revision
flux-system     prod@sha1:23a0d468      True    Applied revision
infrastructure  prod@sha1:23a0d468      True    Applied revision
```

- All applications recovered
- Dependency ordering now enforced
- Future deployments will wait for Vault Injector

## 8. Notes

### CRITICAL WARNINGS

**WARNING 1: NEVER RENAME FLUX KUSTOMIZATIONS WITH PRUNE ENABLED**
```yaml
# DANGEROUS - This DELETES all resources!
# Old
resources:
  - deployments-sync.yaml  # name: "deployments"

# New (CAUSES MASS DELETION)
resources:
  - infrastructure-sync.yaml  # name: "infrastructure" <- NEW NAME
```

**Safe approach:**
```yaml
# Option 1: Keep same name, change path
spec:
  name: deployments  # KEEP SAME NAME
  path: ./new/path

# Option 2: Disable prune first
spec:
  prune: false  # DISABLE PRUNE BEFORE RENAME

# Option 3: Use flux diff to preview
flux diff kustomization infrastructure --path ./kubernetes/prod/deployments/infrastructure
```

**WARNING 2: HEALTHCHECKS CAN CAUSE DEADLOCKS**

If healthCheck references a resource that gets pruned, the Kustomization will NEVER complete.

**WARNING 3: ALWAYS TEST IN DEV FIRST**
```bash
flux diff kustomization <name> --path ./path
flux reconcile kustomization <name> --dry-run
```

### Lessons Learned

1. Flux prune is EXTREMELY dangerous when renaming Kustomizations
2. HelmRelease deletion triggers Helm uninstall - all resources removed
3. HealthChecks can cause deadlocks if they reference pruned resources
4. K8s 1.24+ doesn't auto-create SA token secrets - must create explicitly
5. Always include token secrets in manifests for ServiceAccounts
6. Test Flux changes with `flux diff` first
7. Have a rollback plan - know how to manually bootstrap critical services

### Summary Table

| Issue | Root Cause | Fix | Severity |
|-------|------------|-----|----------|
| WordPress DB fail | No Flux dependency ordering | Split into infrastructure-sync + apps-sync | Medium |
| Remediation crash | In infrastructure folder | Move to apps folder | Medium |
| Vault auth fail | K8s 1.24+ no auto token | Add token secret to manifest | High |
| Complete outage | Flux prune on rename | Manual bootstrap, suspend/resume | **CATASTROPHIC** |

## 9. Workaround (if any)
> For WordPress immediate fix: `kubectl rollout restart deployment wordpress -n apps`
> For complete outage: Manual bootstrap of critical HelmReleases as documented above.
