# TS-K8S-012 | 2026-04-05 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / FluxCD
Sub-techs: FluxCD Kustomization, HelmRelease, CRD ordering, ServiceMonitor,
           kube-prometheus-stack, dependsOn, GitOps
Environment: DEV k8s-dev cluster | flux-system namespace
Re-opened: No

_____________________________________________________________________

[Issue Description]
ServiceMonitor resources fail to deploy because the CRD from kube-prometheus-stack
is not yet installed when Flux tries to apply them.

  flux get kustomization:
  NAME         READY  MESSAGE
  deployments  False  ServiceMonitor/apps/wordpress dry-run failed:
                      no matches for kind "ServiceMonitor" in version
                      "monitoring.coreos.com/v1"

Impact: WordPress and MariaDB application deployments fail to reconcile.
Monitoring integration via ServiceMonitors blocked until CRDs are available.

_____________________________________________________________________

[Analysis]

# Initial Check Notes:

Step 1 — Identify failing resource:
  flux get kustomization → READY: False, check MESSAGE column for the error.

Step 2 — Verify CRD existence:
  kubectl get crd servicemonitors.monitoring.coreos.com
  → Error: the server doesn't have a resource type "servicemonitors"
  CRD not installed.

Step 3 — Check if monitoring stack is deployed:
  kubectl get helmrelease -n monitoring
  → No resources found. kube-prometheus-stack never deployed.

Step 4 — Check monitoring kustomization:
  cat kubernetes/dev/deployments/apps/monitoring/kustomization.yaml
  → resources: []   (empty — monitoring kustomization had no resources defined)

Root cause confirmed: monitoring kustomization was empty so kube-prometheus-stack
was never deployed, yet application deployments referenced ServiceMonitor which
requires the CRD that only kube-prometheus-stack installs.

Flux applies all resources in a Kustomization simultaneously — when CRD provider
(kube-prometheus-stack) and CRD consumer (ServiceMonitor) are in the same
Kustomization, the CRD may not be registered before the consumer is applied.


# Suspected Root Cause
Monitoring kustomization was empty — kube-prometheus-stack never deployed,
ServiceMonitor CRD never registered. Application deployments referencing
ServiceMonitor resources fail because the CRD does not exist. No ordering
mechanism in place between infrastructure (CRDs) and applications.


# More Checks Notes:
N/A — empty kustomization confirmed as the issue.


# Suspected Solution
Option A (quick): comment out ServiceMonitors until monitoring stack deploys.
Option B (permanent): separate Flux Kustomizations for infrastructure and apps
with dependsOn to enforce ordering.


# Test
Applied Option B — created infrastructure-sync.yaml, updated deployments-sync.yaml
with dependsOn, rebuilt flux kustomization.yaml.

Command:
  flux get kustomization
  kubectl get crd servicemonitors.monitoring.coreos.com
  kubectl get servicemonitor -A

Result: PASS
  infrastructure  True  Applied revision: dev@sha1:xxxxx
  deployments     True  Applied revision: dev@sha1:xxxxx
  ServiceMonitor CRD registered, wordpress and mariadb ServiceMonitors created.

_____________________________________________________________________

[Final Root Cause]
Monitoring kustomization was empty — kube-prometheus-stack (which installs the
ServiceMonitor CRD) was never deployed. Application deployments referenced
ServiceMonitor resources which require the CRD. Flux applies all resources in
a Kustomization simultaneously with no built-in CRD-first ordering, so the
ServiceMonitor dry-run fails immediately. No dependsOn was configured between
infrastructure and application Kustomizations.

_____________________________________________________________________

[Final Solution]

Option A — temporary quick fix (comment out ServiceMonitors):
  kubernetes/dev/deployments/apps/wordpress/kustomization.yaml:
    resources:
      - deployment.yaml
      # - servicemonitor.yaml  # enable after kube-prometheus-stack is deployed

Option B — permanent fix (separate Kustomizations with dependsOn):

  1. Create kubernetes/dev/flux/infrastructure-sync.yaml:
       apiVersion: kustomize.toolkit.fluxcd.io/v1
       kind: Kustomization
       metadata:
         name: infrastructure
         namespace: flux-system
       spec:
         interval: 5m0s
         path: ./kubernetes/dev/deployments/apps/monitoring
         prune: true
         wait: true   ← critical: waits for all resources ready before continuing
         sourceRef:
           kind: GitRepository
           name: flux-system

  2. Update kubernetes/dev/flux/deployments-sync.yaml:
       spec:
         dependsOn:
           - name: infrastructure   ← wait for monitoring stack first
         interval: 5m0s
         path: ./kubernetes/dev/deployments

  3. Update kubernetes/dev/flux/kustomization.yaml:
       resources:
         - flux-system
         - infrastructure-sync.yaml
         - deployments-sync.yaml

  4. Remove monitoring from apps kustomization:
       kubernetes/dev/deployments/apps/kustomization.yaml:
         resources:
           # monitoring deployed via infrastructure-sync.yaml
           - logging
           - testing
           - mariadb
           - wordpress

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: Temporary deployment interruption during Kustomization restructuring.
Applications may need manual flux reconcile after the change.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Key lessons:
  1. CRDs must be deployed before resources that depend on them
  2. Flux applies all resources in a Kustomization simultaneously — no built-in ordering
  3. dependsOn is essential for enforcing deployment order between Kustomizations
  4. wait: true on infrastructure Kustomizations ensures CRDs fully registered
     before dependent Kustomizations start

General rule: always use separate Flux Kustomizations for infrastructure
(CRDs, operators, monitoring stack) and applications. Never mix CRD providers
and CRD consumers in the same Kustomization without dependsOn.

Commands reference:
  flux get kustomization                                    check Flux sync status
  kubectl get crd servicemonitors.monitoring.coreos.com    verify CRD registered
  kubectl get servicemonitor -A                             list all ServiceMonitors
  flux reconcile kustomization deployments --with-source   force re-sync

Related files:
  kubernetes/dev/flux/infrastructure-sync.yaml
  kubernetes/dev/flux/deployments-sync.yaml
  kubernetes/dev/flux/kustomization.yaml
  kubernetes/dev/deployments/apps/kustomization.yaml