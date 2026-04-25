# TS-K8S-046 | 2026-04-20 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / FluxCD / Kustomize
Sub-techs: Flux Kustomization, kustomize build, prune, HelmRepository,
           HelmRelease, file consolidation, GitHub dev mode (VSCode web)
Environment: DEV k8s-dev cluster | Flux GitOps
Re-opened: No

_____________________________________________________________________

[Issue Description]
I was consolidating Helm manifests — merging separate helm-repository.yaml and
helm-release.yaml files into single combined files (ingress-nginx-controller.yaml,
metrics-server.yaml). Did this from VSCode over the internet using GitHub dev mode.

The problem: I updated the manifest files but forgot to update the kustomization.yaml
in the ingress folder. It still referenced the old filenames that no longer exist.

Same consolidation was done for the metrics-server folder — that one I got right.
The ingress one I missed.

I didn't run `flux diff` before pushing because I was editing remotely through
GitHub dev mode — no cluster access from there to test against. Just pushed and
let Flux pick it up.

_____________________________________________________________________

[Analysis]

# Initial Check Notes:

After push, Flux infrastructure Kustomization went into failed state.

Command: flux get kustomization

Output:
```
infrastructure  dev@sha1:ec6691cb  False  False
kustomize build failed: accumulating resources: accumulation err='accumulating
resources from 'ingress': read /tmp/kustomization-3015380394/kubernetes/dev/
deployments/infrastructure/ingress: is a directory': recursed accumulation of
path '/tmp/kustomization-3015380394/kubernetes/dev/deployments/infrastructure/
ingress': accumulating resources: accumulation err='accumulating resources from
'helm-repository.yaml': open /tmp/kustomization-3015380394/kubernetes/dev/
deployments/infrastructure/ingress/helm-repository.yaml: no such file or
directory'
```

Command: flux logs --kind=Kustomization

Output (key lines):
```
18:05:11 error Kustomization/infrastructure.flux-system - Reconciliation failed
after 182.117299ms, next try in 5m0s  kustomize build failed: ...
helm-repository.yaml: no such file or directory

18:10:11 error Kustomization/infrastructure.flux-system - Reconciliation failed
after 859.850266ms, next try in 5m0s  (same error)

18:15:12 error Kustomization/infrastructure.flux-system - Reconciliation failed
after 138.732112ms, next try in 5m0s  (same error, repeating every 5m)
```

Meanwhile apps Kustomization was stuck in dependency loop:
```
18:05:10 info Kustomization/apps.flux-system - Dependencies do not meet ready
condition, retrying in 30s
(repeated every 30s for the entire duration)
```

# Suspected Root Cause

Stale kustomization.yaml — still listed the old filenames after file consolidation.

The ingress kustomization.yaml had:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
   - helm-repository.yaml    # <-- deleted, merged into ingress-nginx-controller.yaml
   - helm-release.yaml       # <-- deleted, merged into ingress-nginx-controller.yaml
```

Actual files in the directory:
```
ingress/
  kustomization.yaml
  ingress-nginx-controller.yaml    # <-- the combined file
```

# Key Observation — Why This Was Safe

The kustomize build failed BEFORE reaching the apply/prune stage. Flux never
got a successful build, so it never applied anything, and prune never executed.
Existing cluster resources stayed untouched.

But if the build had succeeded with a different mistake — say I removed the
resource from kustomization.yaml instead of pointing to a missing file — prune
WOULD have deleted the live HelmRelease and HelmRepository from the cluster.
That's the real risk with remote editing without diff.

# After Fix — Diff Before Commit

Once I fixed the kustomization.yaml locally, ran diff to verify:

Command: flux diff kustomization infrastructure --path kubernetes/dev/deployments/infrastructure

Output:
```
HelmRelease/kube-system/csi-driver-nfs drifted
  metadata.generation ± value change - 3 + 4
  spec.values.controller + one map entry added:
    podLabels:
      app: nfs-controller

HelmRelease/ingress-nginx/ingress-nginx drifted
  metadata.generation ± value change - 1 + 2
  spec.values.controller + one map entry added:
    podLabels:
      app: nginx

HelmRelease/kube-system/metrics-server drifted
  metadata.generation ± value change - 1 + 2
  spec.values + one map entry added:
    podLabels:
      app: metrics-server
```

The drifts shown are the pod label additions I'm rolling out today — expected
changes, not related to this bug. The kustomize build now succeeds.

_____________________________________________________________________

[Final Root Cause]
File consolidation (2 files → 1) without updating the kustomization.yaml
resource list. Caused by editing remotely via GitHub dev mode where I couldn't
run `flux diff` to validate before pushing.

_____________________________________________________________________

[Final Solution]
Updated kustomization.yaml to reference the new combined filename:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
   - ingress-nginx-controller.yaml
```

Verified: Yes

_____________________________________________________________________

[Risk Level] MEDIUM

Build failure blocked reconciliation — no destructive action taken. But if the
error type had been different (valid build, missing resource reference), prune
would have deleted live cluster resources. Remote editing without diff access
is the real risk factor here.

_____________________________________________________________________

[References]
- kubernetes/dev/deployments/infrastructure/ingress/kustomization.yaml
- kubernetes/dev/deployments/infrastructure/metrics-server/kustomization.yaml (same consolidation, done correctly)

_____________________________________________________________________

[Draft Notes]
Lesson: when consolidating files in a Flux-managed repo, always update
kustomization.yaml in the same commit. If editing remotely without cluster
access, at minimum do a local `kustomize build` dry run before pushing.
