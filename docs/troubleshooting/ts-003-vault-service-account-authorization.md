# TS-003: Vault Kubernetes Auth - Service Account Not Authorized

## Problem Summary
Pods with Vault Agent injection get stuck in `Init:1/2` or `PodInitializing` state because the Vault Kubernetes auth role doesn't allow the actual service account being used by the pod.

## Symptoms

### Pod stuck in Init state
```bash
$ kubectl get pods -n monitoring
NAME                                        READY   STATUS     RESTARTS   AGE
kube-prometheus-stack-grafana-57c9447f79    0/4     Init:1/2   0          7m58s
```

### Vault agent init container shows auth error
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

### HelmRelease times out
```bash
$ kubectl get helmrelease -n monitoring
NAME                    READY   STATUS
kube-prometheus-stack   False   Helm upgrade failed: timeout waiting for: [Deployment/monitoring/kube-prometheus-stack-grafana status: 'InProgress']
```

## Root Cause
Mismatch between:
1. The service account name configured in Vault's Kubernetes auth role
2. The actual service account name used by the pod

**In this case:**
- Vault role `grafana` was configured to allow service account: `grafana-sa`
- Helm chart created and used service account: `kube-prometheus-stack-grafana`

## Investigation Steps

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

## Solution

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

## Verification

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

## Common Helm Chart Service Account Patterns

| Chart | SA Value Path | Default SA Name |
|-------|--------------|-----------------|
| kube-prometheus-stack (grafana) | `grafana.serviceAccount.name` | `<release>-grafana` |
| kube-prometheus-stack (prometheus) | `prometheus.serviceAccount.name` | `<release>-prometheus` |
| MariaDB | `serviceAccount.name` | `<release>-mariadb` |
| WordPress | `serviceAccount.name` | `<release>-wordpress` |

## Prevention
- Always verify the actual SA name a Helm chart creates: `kubectl get sa -n <namespace>`
- When using Vault injection, test SA authorization before deploying to production
- Document the expected SA names in Vault role configurations
- Use consistent naming conventions: chart name or explicit custom names
