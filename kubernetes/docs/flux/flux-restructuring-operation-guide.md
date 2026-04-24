# Flux Kustomization Safe Restructuring Guide
> Written after TS-K8S-019 disaster. Based on real experience.
> Goal: Split one Kustomization into two (infrastructure + apps) with zero downtime.

---

## Operation Overview — Simple Steps

1. Set `prune: false` on `deployments-sync.yaml` — safety net first
2. Push — Flux reconciles, prune now disabled, nothing deleted
3. Create `infrastructure-sync.yaml` pointing to infrastructure/ folder
4. Remove `deployments-sync.yaml` from kustomization.yaml resources
5. Push — Flux creates `infrastructure` Kustomization, claims all resources, zero downtime
6. Verify `infrastructure` is READY and owns everything
7. Create empty `apps/` folder + `apps-sync.yaml` with `dependsOn: infrastructure`
8. Push — Flux creates `apps` Kustomization, nothing to apply yet
9. Move first app (e.g. wordpress) from infrastructure/ → apps/
10. Push — `infrastructure` releases it, `apps` claims it, brief pod restart
11. Verify app healthy, repeat step 9-10 one app at a time
12. After all apps moved — enable `prune: true` on both Kustomizations
13. Push — migration complete, strict ownership now enforced

---

## The Core Concept Before You Start

Flux tracks resource ownership by **Kustomization name**, not folder name.
Every resource in the cluster gets stamped with the name of the Kustomization that created it.

```
helm-controller → owned by: "deployments"
wordpress       → owned by: "deployments"
vault           → owned by: "deployments"
```

When a Kustomization disappears from Git:
- `prune: true`  → Flux deletes everything it owned. **DANGEROUS.**
- `prune: false` → Flux leaves everything running as orphans. **SAFE.**

Orphan resources keep running normally. Kubernetes doesn't care about Flux ownership labels for scheduling. A new Kustomization can then claim them by applying the same manifests — Flux re-stamps ownership automatically.

---

## The Golden Rules

1. **Never rename a Kustomization while prune: true** — it will delete everything it owns
2. **Never remove a Kustomization file from resources while prune: true** — same result
3. **Folder rename in Git ≠ rename in Flux** — Flux tracks the metadata.name, not the path
4. **prune: false + delete Kustomization = orphans** — resources stay alive, new Kustomization claims them
5. **flux suspend = freeze reconciliation** — use for timing control, not for ownership transfer
6. **One app at a time when moving between Kustomizations** — never move everything at once

---

## The Operation — Split deployments into infrastructure + apps

### Phase 1 — Disable Prune on deployments (Safety First)

Edit `kubernetes/dev/flux/deployments-sync.yaml`:
```yaml
spec:
  prune: false    # ← change from true to false, push this first
```

Push and verify Flux picked it up:
```bash
git push origin dev
kubectl get kustomization deployments -n flux-system -o jsonpath='{.spec.prune}'
# Should return: false
```

Nothing changes in the cluster. This is just your safety net.

---

### Phase 2 — Create infrastructure Kustomization

Create `kubernetes/dev/flux/infrastructure-sync.yaml`:
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure
  namespace: flux-system
spec:
  interval: 5m0s
  path: ./kubernetes/dev/deployments/infrastructure
  prune: false          # keep false until migration is complete
  sourceRef:
    kind: GitRepository
    name: flux-system
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: vault-agent-injector
      namespace: vault
  timeout: 10m
```

Add it to `kubernetes/dev/flux/kustomization.yaml`:
```yaml
resources:
  - flux-system
  - infrastructure-sync.yaml    # ← add
  # - deployments-sync.yaml     # ← comment out or remove (prune already false)
```

Push. Flux creates the `infrastructure` Kustomization object, applies the content,
and re-stamps all infrastructure resources with owner `infrastructure`.
Resources were already running — zero downtime, just ownership transfer.

Verify:
```bash
kubectl get kustomization -n flux-system
# Should now show: flux-system, infrastructure
flux get kustomization infrastructure
# Should show: READY True
```

---

### Phase 3 — Create Empty apps Kustomization

Create `kubernetes/dev/flux/apps-sync.yaml`:
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  interval: 5m0s
  path: ./kubernetes/dev/deployments/apps
  prune: false          # keep false until migration is complete
  sourceRef:
    kind: GitRepository
    name: flux-system
  dependsOn:
    - name: infrastructure    # ← enforces ordering
  timeout: 10m
```

Add to `kubernetes/dev/flux/kustomization.yaml`:
```yaml
resources:
  - flux-system
  - infrastructure-sync.yaml
  - apps-sync.yaml            # ← add
```

Push. Flux creates the `apps` Kustomization. Folder is empty — nothing applied yet.

```bash
kubectl get kustomization apps -n flux-system
# READY: True, nothing owned yet
```

---

### Phase 4 — Move Apps One by One

Move one app folder at a time from `infrastructure/` or old `deployments/` into `apps/`.

Example — moving wordpress:
```bash
git mv kubernetes/dev/deployments/infrastructure/wordpress \
        kubernetes/dev/deployments/apps/wordpress
git commit -m "migrate: move wordpress to apps kustomization"
git push origin dev
```

Watch Flux handle it:
```bash
flux logs --follow --level=info
kubectl get pods -n apps -w
```

What happens:
- `infrastructure` no longer sees wordpress in its path → marks it for removal (but prune: false → does nothing yet)
- `apps` now sees wordpress → applies it, re-stamps ownership to `apps`
- WordPress pod: brief restart as ownership transfers, then back Running

Repeat for each app: monitoring, logging, mariadb, wordpress, remediation.

**Move remediation last** — it depends on vault injection being stable.

---

### Phase 5 — Enable prune After Full Migration

Once all apps are moved and everything is healthy:

```bash
# Verify all apps are running
kubectl get pods -A | grep -v Running | grep -v Completed

# Verify Kustomization ownership is correct
kubectl get kustomization infrastructure -n flux-system -o yaml | grep -A 50 "inventory"
kubectl get kustomization apps -n flux-system -o yaml | grep -A 50 "inventory"
```

Then enable prune on both:
```yaml
# infrastructure-sync.yaml
spec:
  prune: true

# apps-sync.yaml
spec:
  prune: true
  dependsOn:
    - name: infrastructure
```

Push. From this point Flux enforces strict ownership — anything removed from Git gets removed from cluster.

---

## Diagnostic Commands — Use Throughout the Operation

```bash
# Watch all Kustomizations
kubectl get kustomization -n flux-system -w

# See what a Kustomization owns
kubectl get kustomization <name> -n flux-system -o yaml | grep -A 100 "inventory"

# Check resource ownership label
kubectl get helmrelease vault -n vault -o jsonpath='{.metadata.labels}'

# Preview changes before push
flux diff kustomization <name> --path ./kubernetes/dev/deployments/<folder>

# Watch Flux logs live
flux logs --follow --level=info

# Check all HelmReleases healthy
kubectl get helmrelease -A

# Find any stuck pods
kubectl get pods -A | grep -v Running | grep -v Completed
```

---

## Emergency — If Something Goes Wrong Mid-Operation

```bash
# Step 1 — Freeze everything
flux suspend kustomization infrastructure
flux suspend kustomization apps

# Step 2 — Revert the last Git change
git revert HEAD
git push origin dev

# Step 3 — Resume
flux resume kustomization infrastructure
flux resume kustomization apps
flux reconcile kustomization infrastructure --with-source
```

Since prune was false throughout the operation, reverting Git restores the previous state
and no resources were deleted. Safe to retry.