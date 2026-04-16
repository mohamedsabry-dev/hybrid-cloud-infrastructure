# TS-K8S-017 | 2026-04-07 | RESOLVED
_____________________________________________________________________

[Info]
Author:
Domain: Kubernetes / Vault
Sub-techs: Vault Agent Injector, admission webhook, Kubernetes namespaces,
           ReplicaSet, Flux GitOps
Environment: DEV k8s-dev cluster | kube-system → remediation namespace
Re-opened: No

_____________________________________________________________________

[Issue Description]
Deployment shows 0/1 ready, no pods created despite ReplicaSet existing.
Discovered during DR self-healing pod deployment.

  kubectl get deployment remediation -n kube-system:
  NAME         READY  UP-TO-DATE  AVAILABLE
  remediation  0/1    0           0           ← UP-TO-DATE: 0 = no pods ever created

  ReplicaSet events:
  Warning FailedCreate replicaset-controller
  Error creating: admission webhook "vault.hashicorp.com" denied the request:
  error with request namespace: cannot inject into system namespaces: kube-system

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Traced why no pods were created despite the deployment and ReplicaSet existing.

Command:
  kubectl get rs -n kube-system | grep remediation
Output:
  remediation-69dd7f9887  DESIRED:1  CURRENT:0  READY:0
  ReplicaSet exists but pods never created.

Command:
  kubectl get pods -n kube-system -l app=remediation
Output:
  No resources found — creation blocked before pod object is created.

Command:
  kubectl describe rs remediation-69dd7f9887 -n kube-system
Output:
  Warning FailedCreate: admission webhook "vault.hashicorp.com" denied the request:
  cannot inject into system namespaces: kube-system

Vault admission webhook is actively blocking pod creation in kube-system.
This is intentional — Vault blocks injection into system namespaces by default
to prevent sidecars from destabilizing critical cluster components.

System namespaces blocked by Vault by default:
  kube-system, kube-public, kube-node-lease


# Suspected Root Cause
Vault admission webhook denies injection into system namespaces by design.
Remediation deployment was placed in kube-system — webhook blocked every pod
creation attempt before the pod object was even created.


# More Checks Notes:
N/A — admission webhook event in ReplicaSet confirmed the exact cause.


# Suspected Solution
Move deployment to a dedicated non-system namespace (remediation).
Update Vault Kubernetes auth role to allow the new namespace.


# Test
Created remediation namespace, moved all manifests, updated Vault role,
pushed to git, ran Flux reconcile.

Command:
  kubectl get pods -n remediation

Result: PASS — pod created successfully, Vault injection working.

_____________________________________________________________________

[Final Root Cause]
Vault admission webhook is configured by default to deny injection into
Kubernetes system namespaces (kube-system, kube-public, kube-node-lease).
System namespaces contain critical cluster components — injecting sidecars
could destabilize the control plane. Vault enforces this as a security boundary.
Every pod creation attempt in kube-system was denied by the webhook before
the pod object was created.

_____________________________________________________________________

[Final Solution]
Moved remediation deployment to dedicated namespace.

Step 1 — Create namespace manifest:
  apiVersion: v1
  kind: Namespace
  metadata:
    name: remediation

Step 2 — Update all manifests from namespace: kube-system to namespace: remediation:
  configmap.yaml, deployment.yaml, remediation-auth-sa.yaml, vault-ca-secret.yaml

Step 3 — Update kustomization.yaml to include namespace.yaml:
  resources:
    - namespace.yaml
    - configmap.yaml
    - deployment.yaml
    - remediation-auth-sa.yaml
    - priorityclass.yaml
    - vault-ca-secret.yaml

Step 4 — Update Vault Kubernetes auth role:
  vault write auth/kubernetes/role/remediation \
    bound_service_account_names=remediation-sa \
    bound_service_account_namespaces=remediation \
    policies=remediation-policy \
    ttl=1h

Step 5 — Deploy via Flux:
  git add -A && git commit -m "Move remediation to dedicated namespace" && git push origin dev
  flux reconcile kustomization deployments --with-source

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: Update any references to the old kube-system namespace after migration.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Why Vault blocks system namespaces:
  System namespaces contain critical cluster components (API server, scheduler, etc.)
  Injecting sidecars could destabilize the control plane.
  Security boundary — system components should not depend on user-deployed services.

Prevention:
  Always use dedicated namespaces for workloads requiring Vault injection.
  Never deploy Vault-injected pods to system namespaces.

Workaround to allow system namespace injection (NOT recommended):
  injector:
    namespaceSelector:
      matchExpressions:
        - key: kubernetes.io/metadata.name
          operator: NotIn
          values: []
  Do not use this — defeats the security purpose entirely.