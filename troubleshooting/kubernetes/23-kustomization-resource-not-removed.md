# TS-K8S-023 | 2026-04-11 | RESOLVED
_____________________________________________________________________

[Info]
Author:
Domain: Kubernetes / FluxCD
Sub-techs: Flux Kustomization, test resource cleanup, GitOps hygiene
Environment: PROD production cluster | testing namespace
Re-opened: No

_____________________________________________________________________

[Issue Description]
Test pod ingress-test running in production when it should have been excluded.
Discovered while investigating worker2 failure (TS-K8S-022).

  kubectl get pods -n testing:
  ingress-test-5bbc69f45-xv8cl  1/1  Running  2  42h

Impact: LOW — test workload consuming resources in prod, no functional impact.

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Checked kustomization file for the testing namespace.

Command:
  cat kubernetes/prod/deployments/apps/testing/kustomization.yaml

Output:
  resources:
    - ingress-test   ← should have been commented out after testing

ingress-test was left in kustomization.yaml after testing was complete.
Flux continued deploying it on every reconcile.


# Suspected Root Cause
Human error — forgot to remove or comment out test resource from
kustomization.yaml after testing completed.


# More Checks Notes:
N/A — cause obvious from kustomization file content.


# Suspected Solution
Comment out or remove ingress-test from kustomization.yaml.


# Test
Commented out resource, pushed to git, waited for Flux reconcile.

Result: PASS — test pod removed from prod cluster.

_____________________________________________________________________

[Final Root Cause]
ingress-test resource left in prod kustomization.yaml after testing was complete.
Flux treated it as a desired state and kept it running indefinitely.

_____________________________________________________________________

[Final Solution]
Commented out test resource:

  Before:
    resources:
      - ingress-test

  After:
    resources:
      # - ingress-test  # Disabled - testing complete

Flux reconciled and removed the pod. Alternatively:
  kubectl delete deployment ingress-test -n testing  (immediate cleanup)

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: Removing test workload only — no functional impact.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Prevention options:
  Option 1: separate test kustomization not referenced by parent
    kubernetes/prod/deployments/apps/kustomization.yaml  ← prod apps only
    kubernetes/prod/deployments/apps/testing/kustomization.yaml  ← not included

  Option 2: flux suspend instead of commenting
    flux suspend kustomization testing

  Option 3: keep test resources in dev environment only via overlay

General rule for test resources:
  Live in separate kustomization not auto-deployed, OR
  Dev environment only, OR
  Clear naming convention (prefix: test-, debug-), AND
  Cleaned up immediately after testing — never left in prod kustomization.