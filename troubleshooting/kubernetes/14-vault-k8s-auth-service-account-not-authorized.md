# TS-K8S-014 | 2026-04-05 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / Vault
Sub-techs: Vault Agent Injector, Kubernetes auth, ServiceAccount, HelmRelease,
           kube-prometheus-stack, Grafana, Flux
Environment: DEV k8s-dev cluster | monitoring namespace
Re-opened: No

_____________________________________________________________________

[Issue Description]
Grafana pod stuck in Init:1/2 state after kube-prometheus-stack deployment via
Flux HelmRelease. Vault Agent init container failing to authenticate.

  kubectl get pods -n monitoring:
  kube-prometheus-stack-grafana-57c9447f79  0/4  Init:1/2  0  7m58s

  vault-agent-init logs:
  [ERROR] agent.auth.handler: error authenticating:
  URL: PUT https://vault.lab.local:8200/v1/auth/kubernetes/login
  Code: 403. Errors: * service account name not authorized
  backoff=43.47s

  HelmRelease:
  kube-prometheus-stack  False  Helm upgrade failed: timeout waiting for:
  Deployment/monitoring/kube-prometheus-stack-grafana status: 'InProgress'

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Identified the stuck init container and checked its logs.

Command:
  kubectl get pod <pod-name> -n monitoring -o jsonpath='{.spec.serviceAccountName}'

Output:
  kube-prometheus-stack-grafana

Command:
  vault read auth/kubernetes/role/grafana

Output:
  bound_service_account_names:       [grafana-sa]
  bound_service_account_namespaces:  [monitoring]
  policies:                          [grafana]

Mismatch confirmed:
  Vault role expects:  grafana-sa
  Pod is using:        kube-prometheus-stack-grafana

The Helm chart creates a ServiceAccount named <release-name>-grafana by default.
The Vault role was configured with a custom SA name (grafana-sa) that was never
actually created or used by the chart.


# Suspected Root Cause
Mismatch between the ServiceAccount name configured in the Vault Kubernetes auth
role and the actual ServiceAccount name created and used by the Helm chart.
Vault role expected grafana-sa, chart created kube-prometheus-stack-grafana.


# More Checks Notes:
N/A — SA name mismatch confirmed from pod spec and vault role inspection.


# Suspected Solution
Option A (quick): update Vault role to accept the actual SA name from the chart.
Option B (recommended): configure Helm values to use the expected custom SA name.


# Test
Applied Option B — set serviceAccount.create: false, name: grafana-sa in Helm
values, created matching ServiceAccount manifest.

Command:
  kubectl get pod <pod-name> -n monitoring -o jsonpath='{.spec.serviceAccountName}'
  kubectl logs <pod-name> -n monitoring -c vault-agent-init
  kubectl get pods -n monitoring

Result: PASS
  SA: grafana-sa (correct)
  vault-agent-init: authentication successful, rendered grafana-admin secret
  pod: 4/4 Running

_____________________________________________________________________

[Final Root Cause]
kube-prometheus-stack Helm chart creates a ServiceAccount named
kube-prometheus-stack-grafana by default (<release-name>-grafana). The Vault
Kubernetes auth role was configured to allow grafana-sa which does not match.
Vault returns 403 service account name not authorized on every auth attempt.
Pod stays in Init:1/2 indefinitely, HelmRelease times out.

_____________________________________________________________________

[Final Solution]

Option A — update Vault role (quick, no pod restart needed):
  vault write auth/kubernetes/role/grafana \
    bound_service_account_names=kube-prometheus-stack-grafana \
    bound_service_account_namespaces=monitoring \
    policies=grafana \
    ttl=1h

Option B — fix Helm values to use expected SA (recommended, requires pod recreate):

  Wrong (only sets which SA to use, does not control the name):
    grafana:
      serviceAccountName: grafana-sa

  Correct (tell chart not to create its own, use the named one):
    grafana:
      serviceAccount:
        create: false
        name: grafana-sa

  Plus a separate ServiceAccount manifest:
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: grafana-sa
      namespace: monitoring

  Full HelmRelease values example:
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

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: Option A — immediate effect, no pod restart.
Option B — requires pod recreation, brief service interruption.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Common Helm chart SA naming patterns:
  kube-prometheus-stack (grafana)    grafana.serviceAccount.name      default: <release>-grafana
  kube-prometheus-stack (prometheus) prometheus.serviceAccount.name   default: <release>-prometheus
  MariaDB                            serviceAccount.name              default: <release>-mariadb
  WordPress                          serviceAccount.name              default: <release>-wordpress

Key lessons:
  1. Helm charts create ServiceAccounts with release-name prefixes by default
  2. Always verify actual SA name before configuring Vault roles:
     kubectl get sa -n <namespace>
     kubectl get pod <pod> -o jsonpath='{.spec.serviceAccountName}'
  3. serviceAccountName and serviceAccount.name are different fields with
     different behaviours in Helm values
  4. Test Vault authentication in isolation before full deployment

Commands reference:
  kubectl get sa -n <namespace>
  kubectl get pod <pod> -o jsonpath='{.spec.serviceAccountName}'
  kubectl logs <pod> -c vault-agent-init
  vault read auth/kubernetes/role/<role>
  vault write auth/kubernetes/role/<role> bound_service_account_names=<sa>