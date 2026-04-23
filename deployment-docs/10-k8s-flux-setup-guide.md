# Flux Bootstrap + App/Infra Loop — Setup Guide (DEV)

Note: Runs after the Kubernetes cluster is up (k8s-initial-setup-guide.txt) and
before Vault-K8s integration (vault-k8s-integration-guide.txt). Flux is what
reconciles both the infrastructure Helm releases (Vault injector, ingress-nginx,
storage, monitoring, etc.) and the apps.

If you face issues, check:
  troubleshooting/kubernetes/   (Flux-related: TS-K8S-012, 019, 042)
  troubleshooting/github/       (Git workflow: TS-GH-008 on branch merges)

The "why behind the design" — app/infra split, healthCheck on vault-agent-injector,
anti-affinity patch, no priorityClass patch, what Flux does NOT save you from —
lives in:
  kubernetes/dev/flux/DESIGN.md   (same content mirrored in kubernetes/prod/flux/DESIGN.md)

---

## Overview

Flux is installed ONCE per cluster via an Ansible playbook running on master1.
After bootstrap, Flux manages itself — subsequent config changes (anti-affinity
patch, gotk-sync.yaml, etc.) land via Git commits that Flux reconciles on its own.

Two Kustomizations split the workload into a dependency loop:

```
flux-system (bootstrap Kustomization)
  watches: kubernetes/<env>/flux
  │
  ├─► infrastructure-sync.yaml   (Flux Kustomization name: "infrastructure")
  │     path:         kubernetes/<env>/deployments/infrastructure
  │     healthChecks: vault-agent-injector Deployment must be Ready
  │     (CRDs, operators, storage classes, Vault injector, ingress-nginx, monitoring)
  │
  └─► apps-sync.yaml             (Flux Kustomization name: "apps")
        path:      kubernetes/<env>/deployments/apps
        dependsOn: infrastructure
        (WordPress, MariaDB, Grafana, remediation, etcd-backup, nginx-test, etc.)
```

Apps do not reconcile until infrastructure is Ready AND vault-agent-injector is
running. This ordering is what prevents the "app starts, vault injection fails
silently, app crashes minutes later with no secrets" failure mode.

---

## Prerequisites

- Kubernetes cluster running (see k8s-initial-setup-guide.txt). kubectl works
  from master1.
- FreeIPA domain up (Ansible inventory resolves k8s-master1.lab.local).
- GitHub repo accessible. Flux bootstraps against the `dev` branch (or `prod`
  depending on env).
- A GitHub PAT with `repo` write scope, used ONCE for bootstrap — Flux then
  uses an SSH deploy key it creates itself.
- Ansible inventory access to k8s-master1.lab.local as super_bot.

---

## Section 1: GitHub secrets

Two GitHub Actions secrets drive the Ansible playbook:

  GH_ADMIN_PAT_FLUX   → GitHub PAT with `repo` scope (used only during bootstrap
                        to let Flux create the SSH deploy key + commit initial
                        gotk-components.yaml / gotk-sync.yaml)
  GH_USERNAME         → GitHub username that owns the repo

Consumed by any workflow that runs the Flux playbook. Example fetch step:

  - name: Fetch GH Admin PAT and pass to Ansible
    run: |
      GH_TOKEN=${{ secrets.GH_ADMIN_PAT_FLUX }}
      GH_USERNAME=${{ secrets.GH_USERNAME }}
      # pass into ansible-playbook via:
      # -e "gh_admin_pat_token_flux=$GH_TOKEN gh_username=$GH_USERNAME"

Current state: Flux was not part of the original deployment sequence, so there
is no dedicated workflow for it yet. The first bootstrap was run manually with
the two secrets kept encrypted in Ansible Vault (inventory group_vars). The
plan is to add the playbook into the sequenced workflow and switch to GitHub
secret lookup on the next full rebuild.

Current location of the encrypted secrets until the workflow is added:

  ansible/dev/inventory/group_vars/all.yml   (gh_admin_pat_token_flux, gh_username)

---

## Section 2: Run the Flux bootstrap playbook

Playbook: ansible/dev/playbooks/k8s/flux_setup.yml

What it does (on k8s-master1 only):
  - Installs the flux CLI binary (if not already installed)
  - Runs `flux check --pre`
  - Checks if flux-system namespace exists (idempotency guard)
  - If not bootstrapped, runs:
      flux bootstrap github \
        --owner={{ gh_username }} \
        --repository=hybrid-cloud-infrastructure \
        --branch=dev \
        --path=./kubernetes/dev/flux \
        --personal \
        --token-auth=false
  - Waits 2 min for Flux controllers to come up
  - Prints `kubectl -n flux-system get all` as final status

Run from the Ansible LXC (or Mac Mini):

  cd ansible/dev/
  ansible-playbook -i inventory/inventory.ini playbooks/k8s/flux_setup.yml

One-time bootstrap side-effects:
  - Flux generates an SSH deploy key, stores its public half as a repo deploy
    key in GitHub (read + write).
  - Flux commits gotk-components.yaml + gotk-sync.yaml directly to the dev
    branch at kubernetes/dev/flux/.

---

## Section 3: Pull the bootstrap commits into your local dev

After bootstrap, Flux has committed files directly to the dev branch on
GitHub. Your local clone doesn't know about them yet.

  git checkout dev
  git pull origin dev

Files Flux added:
  kubernetes/dev/flux/flux-system/gotk-components.yaml
  kubernetes/dev/flux/flux-system/gotk-sync.yaml

These are generated files — never hand-edit them. For patching Flux controller
config (anti-affinity, replicas, etc.), use the Kustomize patch pattern:
  kubernetes/docs/flux-patch-operation.txt

Other files in kubernetes/dev/flux/ (committed by YOU before or after bootstrap,
NOT by Flux):

  flux-system/flux-pod-anti-affinity.yaml   anti-affinity patch for controllers
  flux-system/kustomization.yaml            wraps gotk + the patch
  infrastructure-sync.yaml                  Flux Kustomization: infrastructure
  apps-sync.yaml                            Flux Kustomization: apps, dependsOn infra
  kustomization.yaml                        top-level, includes all above

Commit these before bootstrap so Flux picks them up on its first reconcile and
creates the infrastructure + apps Kustomizations immediately.

---

## Section 4: What Flux reconciles — the app/infra loop

After bootstrap and first reconcile, three Kustomization objects exist in
the cluster:

  kubectl get kustomization -n flux-system
  # NAME              READY   STATUS
  # flux-system       True    Applied revision: dev@sha1:...
  # infrastructure    True    Applied revision: dev@sha1:...
  # apps              True    Applied revision: dev@sha1:...

infrastructure-sync.yaml key fields:
  spec.path:          ./kubernetes/dev/deployments/infrastructure
  spec.healthChecks:  vault-agent-injector Deployment (vault namespace) Ready
  spec.prune:         true

apps-sync.yaml key fields:
  spec.path:          ./kubernetes/dev/deployments/apps
  spec.dependsOn:     infrastructure
  spec.prune:         true

The healthCheck is the load-bearing part of the pattern. "Ready" in Flux means
"all manifests applied without error" by default — NOT "the thing the apps
need is actually usable." Pinning vault-agent-injector as an explicit
healthCheck keeps infrastructure-sync in Ready: False until the injector is
actually serving mutations. Apps stay blocked on dependsOn until that's true.

Full reasoning — TS-K8S-012 race condition that drove the split; TS-K8S-019
cascade that drove the healthCheck + safe-restructure procedure; TS-K8S-042
retry storm — is in:
  kubernetes/dev/flux/DESIGN.md

---

## Section 5: Verify

  # Flux controllers running (4 pods)
  kubectl get pods -n flux-system
  # expect: source-controller, kustomize-controller, helm-controller, notification-controller

  # All Kustomizations Ready
  flux get kustomizations
  # expect: flux-system, infrastructure, apps   all Ready=True

  # Source reconciling against dev branch
  flux get sources git
  # expect: flux-system   Ready=True, latest commit SHA visible

  # Force reconcile (bypass 1-min poll)
  flux reconcile source git flux-system

---

## Section 6: Prod mirror — DO NOT reverse-merge

When bringing up prod, the Flux bootstrap commits prod's gotk-components.yaml
and gotk-sync.yaml to the `prod` branch (scoped to kubernetes/prod/flux/).
If you then `git merge prod` into dev (or vice-versa), you drag env-specific
files across branches that are intentionally different and start a two-way
merge flow.

TS-GH-008 (troubleshooting/github/8-git-branch-merge-conflicts-flux-gitops.md)
documents the exact failure mode — conflict markers committed into YAML,
Kustomize build errors, spaghetti git history, 50+ files showing as changed
in PRs.

Correct pattern for prod mirror:

  1. Let prod bootstrap commit directly to the prod branch
  2. On dev, do NOT `git merge prod`
  3. Copy the new files MANUALLY from prod branch to dev branch, one direction
     only, swapping env-specific values (subnets, VLANs, paths, etc.)
  4. Commit to dev as a fresh change, not a merge

Matches the general dev→prod mirror discipline used across the repo: content
flows by explicit copy + substitution, never by two-way git merge between
branches with intentionally different content.

---

## Section 7: Common operations after bootstrap

Operational guides live in kubernetes/docs/:

  flux-add-folder-guide.txt                add a new watched folder to Flux
  flux-patch-operation.txt                 patch Flux controllers without touching
                                           gotk-components.yaml
  flux-restructuring-operation-guide.md    safe split / rename procedure
                                           (written after TS-K8S-019)
  local-kubectl-flux-setup.md              Mac Mini setup for `flux diff`
                                           pre-push validation

Most-used commands:

  flux get kustomizations
  flux get sources git
  flux reconcile kustomization <name>
  flux reconcile source git flux-system
  flux suspend kustomization --all        # emergency stop (TS-K8S-042 retry storm)
  flux resume kustomization --all
  flux diff kustomization <name> --path <local>   # pre-push validation

---

## Deployment Order — where this fits

In deployment-docs/README.md sequence:

   9   Kubernetes cluster             k8s-initial-setup-guide.txt
  10   Flux bootstrap (THIS GUIDE)    k8s-flux-setup-guide.txt
  11   Vault-K8s integration          vault-k8s-integration-guide.txt
        (Vault injector HelmRelease is part of infrastructure/, Flux reconciles it)
  12   etcd backup → Vault → S3       k8s-etcd-vault-aws-integration.txt
  13   Endpoint DNS + ingress         enpoint-dns-ingress-exnginx-setup-guide.txt
  14   Remediation                    remediation-integration-guide.txt

Flux bootstrap runs immediately after the K8s cluster is up because almost
everything in steps 11–14 is reconciled BY Flux — Vault's Helm chart, ingress-nginx,
the monitoring stack, and the remediation manifest all land via Flux's
infrastructure/ and apps/ Kustomizations. Flux therefore has to exist before
those steps do useful work.

---

## File Reference

| Component                         | Path                                                                    |
|-----------------------------------|-------------------------------------------------------------------------|
| Flux bootstrap playbook           | ansible/dev/playbooks/k8s/flux_setup.yml                                |
| Ansible group_vars (secrets)      | ansible/dev/inventory/group_vars/all.yml                                |
| Flux-generated bootstrap files    | kubernetes/dev/flux/flux-system/gotk-components.yaml                    |
|                                   | kubernetes/dev/flux/flux-system/gotk-sync.yaml                          |
| Anti-affinity patch               | kubernetes/dev/flux/flux-system/flux-pod-anti-affinity.yaml             |
| Flux-system kustomization         | kubernetes/dev/flux/flux-system/kustomization.yaml                      |
| Infrastructure sync               | kubernetes/dev/flux/infrastructure-sync.yaml                            |
| Apps sync (dependsOn infra)       | kubernetes/dev/flux/apps-sync.yaml                                      |
| Top-level flux kustomization      | kubernetes/dev/flux/kustomization.yaml                                  |
| Design + reasoning hub            | kubernetes/dev/flux/DESIGN.md                                           |
| Flux folder README                | kubernetes/dev/flux/README.md                                           |
| Add-folder guide                  | kubernetes/docs/flux-add-folder-guide.txt                               |
| Patch controller config guide     | kubernetes/docs/flux-patch-operation.txt                                |
| Safe restructure guide            | kubernetes/docs/flux-restructuring-operation-guide.md                   |
| Local kubectl + flux CLI setup    | kubernetes/docs/local-kubectl-flux-setup.md                             |
| Signal flow (git push → cluster)  | deployment-docs/signal-flows/flux.txt                                   |
| TS: CRD race (split origin)       | troubleshooting/kubernetes/12-flux-kustomization-crd-dependency-failure.md |
| TS: restructure cascade           | troubleshooting/kubernetes/19-flux-kustomization-restructure-cascade-failure.md |
| TS: retry storm outage            | troubleshooting/kubernetes/42-flux-retry-storm-cluster-outage.md        |
| TS: branch merge conflicts        | troubleshooting/github/8-git-branch-merge-conflicts-flux-gitops.md      |

Prod mirror: same paths under ansible/prod/, kubernetes/prod/.

---

## Troubleshooting

| Symptom                                         | Likely cause / check                                                 |
|-------------------------------------------------|----------------------------------------------------------------------|
| Bootstrap fails with 401 unauthorized           | GH_ADMIN_PAT_FLUX expired or lacks `repo` scope. Regenerate.         |
| "already bootstrapped" but nothing works        | flux-system namespace exists but controllers crashed. kubectl get pods -n flux-system. |
| flux-system Ready, infrastructure not Ready     | vault-agent-injector healthCheck failing. Check vault namespace.     |
| infrastructure Ready, apps stuck Pending        | apps has dependsOn; wait for next reconcile, or `flux reconcile kustomization apps`. |
| Kustomize build errors after a merge            | Conflict markers committed in YAML. See TS-GH-008. Fix via one-way copy + commit, never reverse-merge. |
| Retry storm / control plane slow                | Unsatisfiable reconcile (e.g., required anti-affinity with no room). `flux suspend kustomization --all`, fix manifest, resume. See TS-K8S-042. |
| gotk-components.yaml lost after bootstrap rerun | Expected — bootstrap regenerates it. Any hand-edits get wiped. Use Kustomize patches instead (flux-patch-operation.txt). |
| `flux diff` from laptop fails with Forbidden    | Laptop's kubeconfig uses a read-only SA. `flux diff` needs PATCH permission even for dry-run. See local-kubectl-flux-setup.md. |

---

## Current limitations (pointer)

Full list in kubernetes/dev/flux/DESIGN.md. Short version:
  - Flux bootstrap is a one-time manual Ansible run, not yet wrapped in a
    GitHub workflow.
  - Secrets for bootstrap live in Ansible Vault (not GitHub Actions secrets)
    because Flux wasn't part of the initial plan — will switch on next rebuild.
  - No `flux diff` pre-push gate in CI yet; recommendation is to run it
    locally from the Mac Mini (see kubernetes/docs/local-kubectl-flux-setup.md).
