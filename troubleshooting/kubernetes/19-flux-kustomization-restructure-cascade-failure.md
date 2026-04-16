# TS-K8S-019 | 2026-04-09 | RESOLVED
# Severity: CATASTROPHIC
# Trigger: Power outage recovery + Flux restructuring done incorrectly
_____________________________________________________________________

[Info]
Author:
Domain: Kubernetes / FluxCD
Sub-techs: Flux Kustomization, prune, dependsOn, healthCheck, HelmRelease,
           Vault Agent Injector, ServiceAccount token, K8s 1.24+ SA tokens,
           Helm uninstall, deadlock, power outage recovery
Environment: DEV k8s-dev cluster | full cluster outage
Re-opened: No

_____________________________________________________________________

[Issue Description]
Goal: split one Flux Kustomization (deployments) that watched everything into two:
  infrastructure — vault, ingress, storage (deploys first)
  apps           — wordpress, monitoring, remediation (deploys after vault ready)

The goal was correct. The execution was wrong. Five mistakes combined caused a
complete cluster outage. All HelmReleases deleted. All vault-injected pods stuck.
Complete deadlock. No external access.

_____________________________________________________________________

[Analysis]

# Initial Check Notes:

_____________________________________________________________________
WRONG STEP 1 — No dependency ordering existed before the outage
_____________________________________________________________________

deployments-sync.yaml watched everything at once with no dependsOn.
During power outage recovery, wordpress pods were created BEFORE
vault-agent-injector was ready → pods came up without vault sidecar
→ no DB password → wordpress down.

Evidence — pod comparison at 12:54 PM:
  database  mariadb-0                    2/2  Running  (vault sidecar present)
  apps      wordpress-85b7f46448-k6qlw   1/1  Running  (sidecar MISSING)

Evidence — vault secrets directory missing inside wordpress pod:
  root@wordpress:/# ls -la /vault/secrets/
  ls: cannot access '/vault/secrets/': No such file or directory

Evidence — annotation missing on wordpress pod:
  MariaDB had: "vault.hashicorp.com/agent-inject-status": "injected"
  WordPress pod: NO vault annotation at all

Evidence — etcd backup confirmed old pods HAD the sidecar:
  ETCDCTL_API=3 etcdctl ... | strings | grep -i "vault-agent"
  vault-agent       ← old pods before outage HAD the sidecar
  vault-agent-init

Evidence — timeline that caused the sidecar to be missing:
  09:00 AM  WordPress pods created (vault injector NOT ready yet)
  11:00 AM  Power outage
  12:14 PM  Vault Injector starts and becomes ready
  12:52 PM  MariaDB pod recreated AFTER injector ready → 2/2 ✓
  12:54 PM  WordPress pod restarts but same old pod → 1/1 ✗

What should have been done: add dependsOn between infrastructure and apps
from day one, before any restructuring.


_____________________________________________________________________
WRONG STEP 2 — Renamed Kustomization with prune: true active
_____________________________________________________________________

Created new files with NEW names while prune: true was still enabled:
  Old: deployments-sync.yaml    name: "deployments"
  New: infrastructure-sync.yaml name: "infrastructure"  ← NEW NAME
  New: apps-sync.yaml           name: "apps"            ← NEW NAME

Flux saw "deployments" disappear from Git → prune kicked in →
deleted EVERYTHING owned by deployments:
  vault HelmRelease deleted     → Helm uninstall ran → vault-agent-injector gone
  ingress-nginx HelmRelease deleted → no external access
  csi-driver-nfs HelmRelease deleted

Evidence — Flux logs showing vault HelmRelease uninstalled:
  flux logs --kind=HelmRelease --name=vault -n vault
  2026-04-09T15:00:37.206Z info HelmRelease/vault.vault -
  uninstalled Helm release for deleted resource

Evidence — all HelmReleases gone:
  kubectl get helmrelease -A
  No resources found

  kubectl get pods -n vault
  No resources found in vault namespace.

Evidence — timeline of the disaster (2 seconds to destroy everything):
  15:00:35  Flux infrastructure kustomization starts reconciling
  15:00:37  Flux UNINSTALLS vault HelmRelease
  15:00:37  vault-agent-injector DELETED
  15:00:37  All HelmReleases DELETED (vault, ingress-nginx, csi-driver-nfs)
  15:00:xx  infrastructure stuck: healthCheck waiting for deleted vault-agent-injector
  15:00:xx  apps stuck: waiting for infrastructure
  15:00:xx  ALL pods with vault injection stuck in Init:0/2
  15:00:xx  ingress-nginx down — no external access

What should have been done: set prune: false on deployments-sync.yaml BEFORE
introducing new Kustomization names.


_____________________________________________________________________
WRONG STEP 3 — Remediation placed in infrastructure folder
_____________________________________________________________________

infrastructure/
  ├── vault/         ← vault-agent-injector lives here
  └── remediation/   ← needs vault injection — deployed SAME TIME as vault!

Remediation deployed at the same time as vault. Injector not ready yet →
remediation pod started without sidecar → CrashLoopBackOff.

Evidence — remediation CrashLoopBackOff:
  kubectl get pods -n remediation
  remediation-56bdddfcd7-4vjhx  0/1  CrashLoopBackOff  5 restarts

  kubectl logs remediation-56bdddfcd7-4vjhx -n remediation
  FileNotFoundError: No such file or directory: '/vault/secrets/proxmox-creds'

What should have been done: anything that needs vault injection goes in apps/,
never in infrastructure/.


_____________________________________________________________________
WRONG STEP 4 — vault-auth token secret not in manifests
_____________________________________________________________________

After prune deleted everything, the vault-auth-token secret was gone.
Kubernetes 1.24+ does not auto-create ServiceAccount token secrets.
Vault could not authenticate any pod → all pods stuck in Init:0/2.

Evidence — vault-agent-init authentication error:
  URL: PUT https://vault.lab.local:8200/v1/auth/kubernetes/login
  Code: 403. Errors: * permission denied

Evidence — secret missing, SA exists but no token:
  kubectl get secret -n vault vault-auth → Error: secrets "vault-auth" not found
  kubectl get sa vault-auth -n kube-system → NAME: vault-auth  AGE: 18m  (SA exists)
  kubectl get secret -n kube-system | grep vault-auth → empty

Evidence — all vault-injected pods stuck:
  apps      wordpress-6d5cdf8c64-rbk6q   0/2  Init:0/2  0  27m
  database  mariadb-0                    0/2  Init:0/1  0  27m
  monitoring kube-prometheus-stack-grafana 0/4 Init:1/2 0  2m

What should have been done: the token secret must be declared explicitly in
the vault manifests so Flux can recreate it on any reconcile.


_____________________________________________________________________
WRONG STEP 5 — healthCheck created a deadlock
_____________________________________________________________________

infrastructure-sync.yaml had:
  healthChecks:
    - kind: Deployment
      name: vault-agent-injector   ← waiting for this
      namespace: vault

But vault-agent-injector was deleted by prune in wrong step 2.
Infrastructure waited forever for something that no longer existed.
Apps waited for infrastructure. Nothing moved. Complete deadlock.

Evidence — the deadlock:
  infrastructure-sync.yaml healthCheck → waiting for vault-agent-injector
  But vault-agent-injector was DELETED by prune
  infrastructure stuck in "Reconciliation in progress" indefinitely
  apps stuck waiting for infrastructure
  COMPLETE DEADLOCK — nothing in the cluster moves

What should have been done: never put a healthCheck on a resource that can
be deleted by prune from the same Kustomization.


# Suspected Root Cause
Five compounding mistakes:
  1. No dependsOn before restructuring — apps deployed before vault ready
  2. Kustomization renamed with prune: true — mass HelmRelease deletion
  3. Remediation in infrastructure folder — deployed same time as vault
  4. vault-auth token not in manifests — deleted by prune, not recreated
  5. healthCheck on prunable resource — caused infinite deadlock


# More Checks Notes:
The correct operation sequence (what should have happened):
  1. Set prune: false on deployments-sync.yaml → push → verify
  2. Create infrastructure-sync.yaml (prune: false, same path as before)
  3. Remove deployments-sync.yaml from kustomization.yaml resources → push
  4. Flux creates infrastructure Kustomization, orphans become owned by it
  5. Create empty apps/ folder + apps-sync.yaml with dependsOn: infrastructure
  6. Move apps one by one from infrastructure/ to apps/
  7. Move remediation LAST (needs vault injection fully stable)
  8. Verify everything healthy → enable prune: true → push
  Zero downtime. No HelmRelease deletions. No deadlock possible.


# Suspected Solution
Break deadlock, manually bootstrap vault, recreate vault-auth token, re-run
vault trust configuration, resume Flux, restart all stuck pods.


# Test
Ran all recovery steps. Verified all pods running with vault sidecar.

Result: PASS — full cluster recovered. All vault-injected pods running 2/2.
Permanent structural fixes applied.

_____________________________________________________________________

[Final Root Cause]
Kustomization renamed while prune: true was active — Flux treated the old name
as a deleted resource and pruned all HelmReleases it owned, triggering Helm
uninstall for vault, ingress-nginx, and csi-driver-nfs. The resulting
healthCheck on the deleted vault-agent-injector created a deadlock. vault-auth
token secret was not in Git so it was not recreated by Flux. K8s 1.24+ does
not auto-create SA token secrets. All vault-injected pods stuck in Init:0/2.
No external access. Complete cluster outage.

_____________________________________________________________________

[Final Solution]

Recovery steps executed:

  # 1. Break the deadlock
  flux suspend kustomization infrastructure

  # 2. Manually bootstrap vault (HelmRelease deleted by prune)
  kubectl apply -f vault-helmrelease.yaml

  # 3. Recreate vault-auth token secret (K8s 1.24+ won't auto-create)
  kubectl apply -f - <<EOF
  apiVersion: v1
  kind: Secret
  metadata:
    name: vault-auth-token
    namespace: kube-system
    annotations:
      kubernetes.io/service-account.name: vault-auth
  type: kubernetes.io/service-account-token
  EOF

  # 4. Re-run vault trust configuration
  ansible-playbook playbooks/k8s/integration-vault-k8s-trust.yml

  # 5. Resume Flux
  flux resume kustomization infrastructure
  flux reconcile kustomization infrastructure --with-source
  flux reconcile kustomization apps

  # 6. Restart all stuck pods
  kubectl delete pod -n apps -l app=wordpress
  kubectl delete pod -n database mariadb-0
  kubectl delete pod -n monitoring -l app.kubernetes.io/name=grafana
  kubectl delete pod -n remediation -l app=remediation

Permanent fixes applied after recovery:
  Flux ordering      infrastructure-sync.yaml + apps-sync.yaml with dependsOn
  Remediation        moved from infrastructure/ to apps/
  vault-auth token   explicit Secret manifest added to vault folder in Git
  K8s 1.24+ SA tokens now declared in Git, recreated by Flux on any reconcile

Failure summary:
  Phase 1  WordPress missing vault sidecar     no dependsOn ordering         Medium
  Phase 2  Remediation CrashLoopBackOff        placed in infrastructure/     Medium
  Phase 3  Vault auth 403 for all pods         vault-auth token deleted       High
  Phase 4  Complete cluster outage             prune deleted all HelmReleases CATASTROPHIC

Verified: Yes

_____________________________________________________________________

[Risk Level] CATASTROPHIC (incident) / LOW (after fixes applied)

_____________________________________________________________________

[References]
- troubleshooting/kubernetes/22-worker-node-failure-cascading-pod-failures.md
- disaster-recovery/task-1-pod-kill/RESULTS.md
- kubernetes/docs/flux_restructuring_operation_guide.md

_____________________________________________________________________

[Draft Notes]

Key lessons:
  1. prune: true + Kustomization rename = mass deletion. ALWAYS disable prune before rename.
  2. HelmRelease deletion = Helm uninstall = all pods gone. Not just the CR — everything.
  3. healthCheck on a prunable resource = potential deadlock. Design carefully.
  4. K8s 1.24+ does not auto-create SA token secrets. Declare them explicitly in Git.
  5. Anything needing vault injection belongs in apps/, never in infrastructure/.
  6. One structural change at a time. Never rename + restructure + split simultaneously.

_____________________________________________________________________
IMPORTANT — What dependsOn does NOT protect against
_____________________________________________________________________

dependsOn is a Flux-level concept. It only controls reconciliation order when
Flux is applying manifests. It has zero effect on runtime pod restarts.

  Scenario                                          dependsOn helps?
  Fresh cluster start — Flux reconciling            YES — apps waits for infra READY
  Power outage recovery — Flux reapplying all       YES — same ordering enforced
  Running pod deleted manually or crashes           NO  — Kubernetes reschedules immediately
  Worker node dies, pods reschedule                 NO  — Kubernetes scheduler, no Flux

Proven by TS-K8S-022 DR test (2026-04-11):
  kubectl delete pod -n vault -l app.kubernetes.io/name=vault-agent-injector &
  kubectl delete pod -n apps -l app=wordpress

  Result:
    WordPress pods: Running 1/1   ← sidecar NOT injected
                                    ← dependsOn completely bypassed
                                    ← Kubernetes scheduled directly, no Flux involved

  WordPress error:
    mysqli_real_connect(): Access denied for user 'wordpress'
    Error establishing a database connection

What actually protects at runtime — vault-agent-injector HA (fix in TS-K8S-022):
  injector:
    replicas: 2
    affinity:
      podAntiAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app.kubernetes.io/name: vault-agent-injector
            topologyKey: kubernetes.io/hostname

  With 2 replicas on separate masters:
    Replica A → master1
    Replica B → master2
    master1 crashes or injector pod dies
    → Replica B still serving webhook immediately
    → WordPress pods always get sidecar injected

Two different problems, two different fixes:
  Apps deploy before vault ready on cluster start   → dependsOn + healthCheck in Flux
  Apps restart without vault sidecar at runtime     → replicas: 2 + podAntiAffinity on injector