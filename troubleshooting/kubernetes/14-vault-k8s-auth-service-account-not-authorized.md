# TS-K8S-014 | 2026-04-05 | RESOLVED

## 1. Context

- **System:** HashiCorp Vault with Kubernetes authentication
- **Environment:** Development cluster (dev), monitoring namespace
- **Related Components:** Vault Agent Injector, Kubernetes ServiceAccounts, kube-prometheus-stack Helm chart, Grafana
- **Discovered During:** Deployment of kube-prometheus-stack via Flux HelmRelease

## 2. Issue

**Symptom:** Pods with Vault Agent injection get stuck in `Init:1/2` or `PodInitializing` state because the Vault Kubernetes auth role doesn't allow the actual service account being used by the pod.

**Error - Pod stuck in Init state:**
```bash
$ kubectl get pods -n monitoring
NAME                                        READY   STATUS     RESTARTS   AGE
kube-prometheus-stack-grafana-57c9447f79    0/4     Init:1/2   0          7m58s
```

**Error - Vault agent init container shows auth error:**
```bash
$ kubectl logs kube-prometheus-stack-grafana-xxx -n monitoring -c vault-agent-init
2026-04-05T18:24:43.759Z [ERROR] agent.auth.handler: error authenticating:
  error=
  | Error making API request.
  |
  | URL: PUT https://vault.lab.local:8200/v1/auth/kubernetes/login
  | Code: 403. Errors:
  |
  | * service account name not authorized
   backoff=43.47s
```

**Error - HelmRelease times out:**
```bash
$ kubectl get helmrelease -n monitoring
NAME                    READY   STATUS
kube-prometheus-stack   False   Helm upgrade failed: timeout waiting for: [Deployment/monitoring/kube-prometheus-stack-grafana status: 'InProgress']
```

**Impact:** Grafana deployment blocked. Monitoring stack incomplete. HelmRelease stuck in failed state.

## 3. Analysis

### Step 1: Identify the stuck init container
```bash
$ kubectl describe pod kube-prometheus-stack-grafana-xxx -n monitoring
# Look for Events showing vault-agent-init container starting
```

### Step 2: Check vault-agent-init logs
```bash
$ kubectl logs <pod-name> -n monitoring -c vault-agent-init
# Look for "service account name not authorized" error
```

### Step 3: Find the actual service account being used
```bash
$ kubectl get pod <pod-name> -n monitoring -o jsonpath='{.spec.serviceAccountName}'
kube-prometheus-stack-grafana
```

### Step 4: Check what Vault role expects
```bash
$ vault read auth/kubernetes/role/grafana
Key                                 Value
---                                 -----
bound_service_account_names         [grafana-sa]
bound_service_account_namespaces    [monitoring]
policies                            [grafana]
```

**Evidence from session:**
```bash
$ kubectl get pod kube-prometheus-stack-grafana-57c9447f79-cc4dk -n monitoring -o jsonpath='{.spec.serviceAccountName}'
kube-prometheus-stack-grafana
# But Vault expected: grafana-sa
```

## 4. Root Cause

Mismatch between:
1. The service account name configured in Vault's Kubernetes auth role
2. The actual service account name used by the pod

**In this case:**
- Vault role `grafana` was configured to allow service account: `grafana-sa`
- Helm chart created and used service account: `kube-prometheus-stack-grafana`

The Helm chart by default creates a ServiceAccount named `<release-name>-grafana`, but the Vault role was expecting a custom ServiceAccount name `grafana-sa`.

## 5. Solution

### Option A: Update Vault Role (Quick Fix)
Change Vault to accept the actual service account name:
```bash
$ vault write auth/kubernetes/role/grafana \
    bound_service_account_names=kube-prometheus-stack-grafana \
    bound_service_account_namespaces=monitoring \
    policies=grafana \
    ttl=1h
```

### Option B: Fix Helm Values (Recommended)
Configure the Helm chart to use the expected service account name.

**Wrong configuration:**
```yaml
grafana:
  serviceAccountName: grafana-sa  # This only sets which SA to use, not the name
```

**Correct configuration:**
```yaml
grafana:
  serviceAccount:
    create: false        # Don't create, use existing
    name: grafana-sa     # Use this specific SA name
```

**If you have a separate ServiceAccount manifest:**
```yaml
# service-account.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: grafana-sa
  namespace: monitoring
```

Then set `create: false` in Helm values so it uses your existing SA instead of creating its own.

**Full working example:**
```yaml
# helm-release.yaml
grafana:
  serviceAccount:
    create: false
    name: grafana-sa

  podAnnotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "grafana"
    vault.hashicorp.com/agent-inject-secret-grafana-admin: "secret/data/grafana/config"
    vault.hashicorp.com/agent-inject-template-grafana-admin: |
      {{- with secret "secret/data/grafana/config" -}}
      GF_SECURITY_ADMIN_USER={{ .Data.data.admin_user }}
      GF_SECURITY_ADMIN_PASSWORD={{ .Data.data.admin_password }}
      {{- end }}
```

### Common Helm Chart Service Account Patterns

| Chart | SA Value Path | Default SA Name |
|-------|--------------|-----------------|
| kube-prometheus-stack (grafana) | `grafana.serviceAccount.name` | `<release>-grafana` |
| kube-prometheus-stack (prometheus) | `prometheus.serviceAccount.name` | `<release>-prometheus` |
| MariaDB | `serviceAccount.name` | `<release>-mariadb` |
| WordPress | `serviceAccount.name` | `<release>-wordpress` |

### Prevention Measures
- Always verify the actual SA name a Helm chart creates: `kubectl get sa -n <namespace>`
- When using Vault injection, test SA authorization before deploying to production
- Document the expected SA names in Vault role configurations
- Use consistent naming conventions: chart name or explicit custom names

## 6. Solution Risk

- **Risk Level:** Low
- **Potential Impact:**
  - Option A (Vault update): Immediate effect, no pod restart needed
  - Option B (Helm values): Requires pod recreation, brief service interruption

## 7. Impact After Fix

**Observed Results:**

### Step 1: Check pod uses correct SA
```bash
$ kubectl get pod <pod-name> -n monitoring -o jsonpath='{.spec.serviceAccountName}'
grafana-sa
```

### Step 2: Verify vault-agent-init succeeds
```bash
$ kubectl logs <pod-name> -n monitoring -c vault-agent-init
2026-04-05T18:34:56.453Z [INFO]  agent.auth.handler: authentication successful, sending token to sinks
2026-04-05T18:34:56.490Z [INFO]  agent: (runner) rendered "(dynamic)" => "/vault/secrets/grafana-admin"
```

### Step 3: Verify pod is running
```bash
$ kubectl get pods -n monitoring
NAME                                        READY   STATUS    RESTARTS   AGE
kube-prometheus-stack-grafana-76d659dc49    4/4     Running   0          2m
```

## 8. Notes

### Lessons Learned
- Helm charts often create ServiceAccounts with release-name prefixes
- Always check actual SA names before configuring Vault roles
- The `serviceAccountName` field and `serviceAccount.name` field have different behaviors in Helm charts
- Test Vault authentication in isolation before full deployment

### Commands Reference
```bash
kubectl get sa -n <namespace>                                          # List service accounts
kubectl get pod <pod> -o jsonpath='{.spec.serviceAccountName}'         # Get pod's SA
kubectl logs <pod> -c vault-agent-init                                 # Check Vault agent logs
vault read auth/kubernetes/role/<role>                                 # Read Vault role config
vault write auth/kubernetes/role/<role> bound_service_account_names=<sa>  # Update Vault role
```

### Related Files
- Vault Kubernetes auth role configuration
- Helm release values for kube-prometheus-stack
- ServiceAccount manifests (if using custom SAs)

### References
- Vault Kubernetes Auth Method documentation
- kube-prometheus-stack Helm chart values

## 9. Workaround

**Quick fix:** Update the Vault role to accept the actual ServiceAccount name created by the Helm chart:
```bash
vault write auth/kubernetes/role/grafana \
    bound_service_account_names=kube-prometheus-stack-grafana \
    bound_service_account_namespaces=monitoring \
    policies=grafana \
    ttl=1h
```

This allows immediate resolution without modifying Helm values or recreating pods.
