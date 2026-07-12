Flux GitOps Reconciliation — Git Push to Running Resources (Summary Trace)
============================================================================

pre-trace (one-time setup):
  Flux bootstrapped on cluster (source, kustomize, helm, notification controllers)
    → GitRepository configured with SSH deploy key, 1-minute poll
      → two Kustomizations: infrastructure (no deps) → apps (dependsOn: infrastructure)

optional pre-push: flux diff kustomization --path <local>
  → kustomize build locally → dry-run each resource against API server
    → shows unchanged / drifted / created / deleted / validation errors
      → catches schema typos + accidental prunes before commit

developer pushes to branch → GitHub stores new SHA
  → source-controller polls (1 min) → detects new SHA
    → pulls repo → verifies integrity → creates Artifact (SHA + checksum + path)
      → kustomize-controller notified of new Artifact

→ kustomize-controller checks dependsOn graph
  → infrastructure Kustomization: no deps → processes first
    → apps Kustomization: blocked until infrastructure reaches READY: true

→ for each Kustomization in dependency order:
  → fetch Artifact from source-controller → extract configured path only
    → kustomize build → walks folder tree → resolves + patches
      → produces one flat manifest stream, sorted:
        Namespace → CRDs/Secrets/ConfigMaps → RBAC → Services/Deployments → rest

→ dry-run validation (atomic gate):
  → PATCH ?dryRun=All for each resource → API server validates RBAC + webhooks + schema
    → ANY failure → STOP, apply nothing this cycle (no partial state)
      → ALL pass → proceed to real apply

→ real apply: PATCH each resource → API server writes to etcd
  → stamps Flux ownership labels on every resource
    → edge case: dry-run passed but apply fails → partial state

→ prune (if prune: true): delete resources in old inventory but not in current build
  → WARNING: Kustomization rename with prune = mass deletion (TS-K8S-019)

→ health check (if configured): wait for listed resources to report Ready
  → timeout → Kustomization marked not READY
    → WARNING: healthCheck on deleted resource = deadlock

→ status update: READY: true → unblocks dependsOn children (apps starts its own cycle)
  → READY: false → children remain blocked
    → unsatisfiable failure → Flux retries every interval without backoff
      → control-plane pressure (TS-K8S-042 retry storm)

parallel path — Helm controller:
  source-controller polls HelmRepository (1h) → downloads chart → Artifact
    → helm-controller renders with HelmRelease values
      → install / upgrade / no-op / uninstall (if HelmRelease pruned)

drift correction (every 5m, no git change needed):
  manual edit → Flux detects diff → re-applies from Git → reverted
  manual delete → Flux recreates from build output
  manual apply without ownership label → Flux ignores, stays unmanaged

self-management: gotk-sync.yaml → watches flux directory → creates Kustomizations
  → patches merge onto gotk-components.yaml → replicas, affinity, limits via Git

break-glass (TS-K8S-042): suspend all → diagnose → fix in Git → resume one at a time
