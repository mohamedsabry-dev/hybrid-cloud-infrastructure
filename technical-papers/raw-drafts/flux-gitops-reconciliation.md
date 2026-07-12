Flux GitOps Reconciliation — From Git Push to Running Resources
================================================================

Traces how a git push flows through Flux's controller chain to
become running K8s resources. Covers the 7-step reconciliation
pipeline, dependency ordering, dry-run validation gate, prune
behavior, Helm controller, drift correction, and the emergency
break-glass procedure.


### Pre-Push Validation — flux diff

before committing, the developer can validate locally:

    laptop kubeconfig → flux diff kustomization <name> --path <local-path>
      |
      +-- kustomize build runs locally
      +-- sends each resource to API server with ?dryRun=All
      +-- API server runs the SAME validation path as real reconcile:
      |     RBAC → admission webhooks → schema validation
      |     (CRD OpenAPI, enums, required fields)
      |
      +-- returns per resource:
            ✓ unchanged
            ► drifted (current state differs from desired)
            + created (new resource)
            - deleted (would be pruned)
            422 validation error

    catches schema typos, wrong enums, accidental prunes BEFORE
    the commit hits the cluster. same validation path the real
    reconcile would hit (step 3 below).

    habit that would have prevented TS-K8S-019 (mass prune from
    Kustomization rename) and TS-K8S-042 (retry storm from bad
    manifest).


### Source Controller — Detecting Changes

    git push → GitHub stores commit (new SHA)
      |
      +-- source-controller polls every 1 minute via SSH deploy key
      |
      +-- same SHA as last pull → skip, wait next interval
      |
      +-- new SHA detected:
            pulls repo → verifies integrity
            creates Artifact:
              +-- commit SHA
              +-- checksum
              +-- local path to fetched content
            kustomize-controller notified of new Artifact


### Dependency Ordering — dependsOn

before processing, kustomize-controller checks dependencies:

    infrastructure Kustomization
      +-- processes FIRST (no dependsOn)
      +-- includes: namespaces, CRDs, RBAC, Vault injector,
      |   ingress-nginx, monitoring stack
      +-- healthCheck on vault-agent-injector
      |   (apps depend on it at runtime)
      +-- must reach READY: true before apps can proceed

    apps Kustomization
      +-- dependsOn: infrastructure
      +-- blocked until infrastructure reports READY: true
      +-- includes: wordpress, mariadb, nginx, app-level resources

    if infrastructure fails or its healthCheck times out:
      apps stay blocked, READY: false, never reconciled this cycle.


### The 7-Step Reconciliation Pipeline

for each Kustomization in dependency order:

    STEP 1 — Fetch
      +-- fetch Artifact from source-controller
      +-- extract only the configured path (not full repo)

    STEP 2 — Build
      +-- kustomize build → walks folder tree recursively
      +-- resolves resources → applies patches
      +-- produces ONE flat manifest stream
      +-- resources SORTED for safe apply order:
            1. Namespace
            2. CRD + ServiceAccount + Secret + ConfigMap + StorageClass
            3. ClusterRole / ClusterRoleBinding / Role / RoleBinding
            4. Service / Deployment / StatefulSet / DaemonSet / Pod
            5. Everything else (HelmRepository, HelmRelease, custom resources)

      sort handles hard dependencies:
        Namespace must exist before namespaced resources
        CRD must exist before custom resources
      soft references (HelmRelease → HelmRepository) rely on
      controller retries, not sort order.

    STEP 3 — Dry-Run Validation (atomic gate)
      +-- for EACH resource: PATCH ?dryRun=All
      +-- API server runs: RBAC + admission webhooks + schema validation
      +-- if ANY resource fails dry-run:
      |     STOP → report ValidationFailed → apply NOTHING this cycle
      |     atomic failure: no partial state
      |     prior resources from past reconciles untouched
      |     catches: CRD schema typos, wrong enum values,
      |     missing required fields, RBAC denials, missing CRDs
      +-- if ALL dry-runs pass → proceed to step 4

    STEP 4 — Real Apply
      +-- for each resource: PATCH → API server writes to etcd
      +-- stamps ownership labels on every resource:
      |     kustomize.toolkit.fluxcd.io/name: infrastructure
      |     kustomize.toolkit.fluxcd.io/namespace: flux-system
      +-- edge case: dry-run passed but real apply fails
      |   (webhook drift, quota hit between dry-run and apply)
      |   → partial apply: resources before failure stay in etcd,
      |     resources after are skipped

    STEP 5 — Prune
      +-- if prune: true in Kustomization spec
      +-- deletes any resource previously in inventory
      |   but NOT in current build output
      +-- WARNING: rename Kustomization with prune: true =
      |   mass deletion — new name has empty inventory,
      |   old name's resources are orphaned then pruned
      |   (this was TS-K8S-019)
      +-- SAFETY: flux diff shows "- deleted" lines for every
          prune target BEFORE commit

    STEP 6 — Health Check
      +-- if healthCheck defined in Kustomization spec
      +-- waits until listed resources report Ready
      +-- timeout → mark Kustomization not READY
      +-- WARNING: healthCheck on a deleted resource =
          deadlock forever (waits for something that no longer exists)

    STEP 7 — Update Status
      +-- READY: true → unblocks dependsOn children
      +-- READY: false → children remain blocked
      +-- if failure is unsatisfiable (e.g. requiredDuringScheduling
          with no available node), Flux retries every interval
          without smart backoff → control-plane pressure
          (this was TS-K8S-042 — retry storm)


### Helm Controller — Parallel Path

runs alongside kustomize-controller, watches HelmRelease objects:

    source-controller polls HelmRepository (1h interval)
      +-- downloads chart → creates Artifact
      |
      +-- helm-controller fetches chart Artifact
      +-- renders with values block from HelmRelease spec
      |
      +-- no existing release → helm install
      +-- release exists + changed → helm upgrade
      +-- nothing changed → no-op
      +-- HelmRelease deleted (by prune) → helm uninstall
          → ALL chart resources gone
          (this is what made TS-K8S-019 catastrophic —
          prune deleted HelmRelease → helm uninstall removed
          everything the chart had created)


### Notification Controller

watches all Flux objects for status changes:

    Alert + Provider configured
      +-- sends to Slack / Teams / GitHub on status transitions

    receives GitHub webhook (if configured)
      +-- triggers immediate reconcile
      +-- bypasses the 1-minute poll interval


### Drift Correction — Every 5 Minutes

even with no git change, kustomize-controller re-runs the full
7-step cycle every interval (default 5m):

    manual kubectl edit on a Flux-managed resource
      +-- Flux detects diff on next reconcile
      +-- re-applies desired state from Git → edit reverted

    manual kubectl delete on a Flux-managed resource
      +-- resource still in build output
      +-- Flux recreates it on next reconcile

    manual kubectl apply (no ownership label)
      +-- Flux ignores it — resource stays unmanaged
      +-- no conflict, no revert


### Flux Manages Itself

Flux's own controllers are managed via GitOps:

    gotk-sync.yaml (root Kustomization)
      +-- watches ./kubernetes/<env>/flux directory
      +-- finds infrastructure-sync.yaml + apps-sync.yaml
      +-- creates those Kustomization objects
      |
      +-- patches in kustomization.yaml merge onto gotk-components.yaml
          Flux configures its own controllers:
          replicas, anti-affinity, resource limits — all via Git


### Emergency Break-Glass

when Flux retry is actively hurting the cluster (TS-K8S-042 pattern —
unsatisfiable manifest causing retry storm, control-plane under pressure):

    step 1 — stop the bleeding:
      flux suspend kustomization --all
      flux suspend helmrelease --all -A

    step 2 — diagnose:
      kubectl / crictl if API server is struggling
      identify which manifest is causing the loop

    step 3 — fix:
      fix the manifest in Git, push

    step 4 — resume carefully:
      flux resume kustomization --all
      verify one Kustomization at a time
