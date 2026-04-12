# TS-K8S-019 — Incident Review
> Date: 2026-04-09 | Severity: CATASTROPHIC | Status: RESOLVED
> Trigger: Power outage recovery + Flux restructuring done incorrectly

---

## What We Were Trying To Do

Split one Flux Kustomization (`deployments`) that watched everything into two:
- `infrastructure` — vault, ingress, storage (deploys first)
- `apps` — wordpress, monitoring, remediation (deploys after vault is ready)

The goal was correct. The execution was wrong.

---

## What We Did Wrong — Step by Step

### ❌ Wrong Step 1: No dependency ordering existed before the outage

```yaml
# deployments-sync.yaml
path: ./kubernetes/dev/deployments   # watched everything at once

# deployments/kustomization.yaml
resources:
  - infrastructure   # vault here
  - apps             # wordpress here — no dependency on vault!
```

Flux applied both simultaneously. During power outage recovery, wordpress pods
were created BEFORE vault-agent-injector was ready → pods came up without vault
sidecar → no DB password → wordpress down.

**Evidence — pod comparison at 12:54 PM:**
```bash
[root@k8s-master1 ~]# kubectl get pods -n database
NAME        READY   STATUS    RESTARTS   AGE
mariadb-0   2/2     Running   0          12m    # vault-agent sidecar present

[root@k8s-master1 ~]# kubectl get pods -n apps
NAME                         READY   STATUS    RESTARTS   AGE
wordpress-85b7f46448-k6qlw   1/1     Running   0          4h5m   # sidecar MISSING
```

**Evidence — vault secrets directory missing inside wordpress pod:**
```bash
root@wordpress-85b7f46448-rwxx9:/# ls -la /vault/secrets/
ls: cannot access '/vault/secrets/': No such file or directory
```

**Evidence — annotation missing on wordpress pod:**
```bash
# MariaDB (working) had this annotation:
"vault.hashicorp.com/agent-inject-status": "injected"

# WordPress pod had NO vault annotation at all
```

**Evidence — etcd backup confirmed old pods HAD the sidecar:**
```bash
ETCDCTL_API=3 etcdctl ... | strings | grep -i "vault-agent"
vault-agent        # old pods before outage HAD the sidecar
vault-agent-init
```

**Evidence — timeline that caused it:**
```
09:00 AM — WordPress pods created (vault injector NOT ready yet)
11:00 AM — Power outage
12:14 PM — Vault Injector starts and becomes ready
12:52 PM — MariaDB pod recreated AFTER injector ready → 2/2 ✅
12:54 PM — WordPress pod restarts but same old pod → 1/1 ❌
```

**What should have been done:** `dependsOn` between infrastructure and apps
from day one, before any restructuring.

---

### ❌ Wrong Step 2: Renamed Kustomization with prune: true active

Created new files with NEW names while `prune: true` was still enabled:

```
Old: deployments-sync.yaml   (name: "deployments")
New: infrastructure-sync.yaml (name: "infrastructure")  ← NEW NAME
New: apps-sync.yaml           (name: "apps")            ← NEW NAME
```

Flux saw `deployments` disappear from Git → prune kicked in →
deleted EVERYTHING owned by `deployments`:
- vault HelmRelease deleted → Helm uninstall ran → vault-agent-injector gone
- ingress-nginx HelmRelease deleted → no external access
- csi-driver-nfs HelmRelease deleted

**Evidence — Flux logs showing vault HelmRelease uninstalled:**
```bash
[root@k8s-master1 tmp]# flux logs --kind=HelmRelease --name=vault -n vault
2026-04-09T15:00:37.206Z info HelmRelease/vault.vault - uninstalled Helm release for deleted resource
```

**Evidence — all HelmReleases gone:**
```bash
[root@k8s-master1 tmp]# kubectl get helmrelease -A
No resources found

[root@k8s-master1 tmp]# kubectl get pods -n vault
No resources found in vault namespace.
```

**Evidence — timeline of the disaster (2 seconds to destroy everything):**
```
15:00:35 — Flux infrastructure kustomization starts reconciling
15:00:37 — Flux UNINSTALLS vault HelmRelease
15:00:37 — vault-agent-injector DELETED
15:00:37 — All HelmReleases DELETED (vault, ingress-nginx, csi-driver-nfs)
15:00:xx — infrastructure stuck: healthCheck waiting for deleted vault-agent-injector
15:00:xx — apps stuck: waiting for infrastructure
15:00:xx — ALL pods with vault injection stuck in Init:0/2
15:00:xx — ingress-nginx down — no external access
```

**What should have been done:** Set `prune: false` on `deployments-sync.yaml`
BEFORE introducing new Kustomization names.

---

### ❌ Wrong Step 3: Remediation placed in infrastructure folder

```
infrastructure/
  ├── vault/          # vault-agent-injector lives here
  └── remediation/    # needs vault injection — deployed SAME TIME as vault!
```

Remediation deployed at the same time as vault. Vault injector not ready yet →
remediation pod started without sidecar → CrashLoopBackOff.

**Evidence — remediation CrashLoopBackOff:**
```bash
[root@k8s-master1 ~]# kubectl get pods -n remediation
NAME                           READY   STATUS             RESTARTS      AGE
remediation-56bdddfcd7-4vjhx   0/1     CrashLoopBackOff   5 (2m36s ago) 7m47s

[root@k8s-master1 ~]# kubectl logs remediation-56bdddfcd7-4vjhx -n remediation
FileNotFoundError: [Errno 2] No such file or directory: '/vault/secrets/proxmox-creds'
```

**What should have been done:** Anything that needs vault injection goes in
`apps/`, never in `infrastructure/`.

---

### ❌ Wrong Step 4: vault-auth token secret not in manifests

After prune deleted everything, the `vault-auth-token` secret was gone.
Kubernetes 1.24+ does not auto-create ServiceAccount token secrets.
Vault could not authenticate any pod → all pods stuck in `Init:0/2`.

**Evidence — vault-agent-init authentication error:**
```bash
2026-04-09T14:09:53.975Z [ERROR] agent.auth.handler: error authenticating:
  error=
  | URL: PUT https://vault.lab.local:8200/v1/auth/kubernetes/login
  | Code: 403. Errors:
  | * permission denied
```

**Evidence — secret missing, SA exists but no token:**
```bash
[root@k8s-master1 ~]# kubectl get secret -n vault vault-auth -o jsonpath='{.data.token}' | base64 -d
Error from server (NotFound): secrets "vault-auth" not found

[root@k8s-master1 ~]# kubectl get sa vault-auth -n kube-system
NAME         AGE
vault-auth   18m        # SA exists

[root@k8s-master1 ~]# kubectl get secret -n kube-system | grep vault-auth
# Empty — no token secret!
```

**Evidence — all vault-injected pods stuck:**
```bash
[root@k8s-master1 ~]# kubectl get pods -A | grep -E "Init|vault"
apps         wordpress-6d5cdf8c64-rbk6q        0/2   Init:0/2   0   27m
database     mariadb-0                         0/2   Init:0/1   0   27m
monitoring   kube-prometheus-stack-grafana-*   0/4   Init:1/2   0   2m
```

**What should have been done:** The token secret must be declared explicitly
in the vault manifests so Flux can recreate it on any reconcile.

---

### ❌ Wrong Step 5: healthCheck created a deadlock

```yaml
# infrastructure-sync.yaml
healthChecks:
  - kind: Deployment
    name: vault-agent-injector   # waiting for this
    namespace: vault
```

But vault-agent-injector was deleted by prune in step 2.
Infrastructure waited forever for something that no longer existed.
Apps waited for infrastructure. Nothing moved. Complete deadlock.

**Evidence — the deadlock explained:**
```
infrastructure-sync.yaml healthCheck → waiting for vault-agent-injector
But vault-agent-injector was DELETED by prune in wrong step 2

Result:
1. infrastructure waits for vault-agent-injector → never comes → stuck
2. apps dependsOn infrastructure → never starts → stuck
3. Nothing in the cluster moves → complete outage
```

**Evidence — infrastructure stuck in reconciliation:**
```
15:00:xx — infrastructure stuck in "Reconciliation in progress"
           healthCheck waiting for vault-agent-injector that no longer exists
15:00:xx — apps stuck waiting for infrastructure
15:00:xx — COMPLETE DEADLOCK
```

**What should have been done:** Never put a healthCheck on a resource
that can be deleted by prune from the same Kustomization.

---

## The Correct Operation (What Should Have Happened)

```
1. Set prune: false on deployments-sync.yaml → push → verify
2. Create infrastructure-sync.yaml (prune: false, same path as before)
3. Remove deployments-sync.yaml from kustomization.yaml resources → push
4. Flux creates infrastructure Kustomization, orphans become owned by infrastructure
5. Create empty apps/ folder + apps-sync.yaml with dependsOn: infrastructure → push
6. Move apps one by one from infrastructure/ to apps/
7. Move remediation LAST (it needs vault injection to be fully stable)
8. Verify everything healthy → enable prune: true on both → push
```

Zero downtime. No HelmRelease deletions. No deadlock possible.

---

## Recovery Steps That Were Actually Run

```bash
# 1. Break the deadlock
flux suspend kustomization infrastructure

# 2. Manually bootstrap vault (HelmRelease was deleted by prune)
kubectl apply -f vault-helmrelease.yaml

# 3. Recreate vault-auth token secret (deleted by prune, K8s 1.24+ won't auto-create)
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
cd ansible/dev
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
```

---

## Permanent Fixes Applied After Recovery

| Fix | What Changed |
|---|---|
| Flux ordering | Created `infrastructure-sync.yaml` + `apps-sync.yaml` with `dependsOn` |
| Remediation location | Moved from `infrastructure/` to `apps/` |
| vault-auth token | Added explicit Secret manifest to vault folder |
| K8s 1.24+ SA tokens | Now declared in Git, recreated by Flux on any reconcile |

---

## Failure Summary

| Phase | What Went Wrong | Root Cause | Severity |
|---|---|---|---|
| Phase 1 | WordPress missing vault sidecar | No dependsOn ordering | Medium |
| Phase 2 | Remediation CrashLoopBackOff | Placed in infrastructure folder | Medium |
| Phase 3 | Vault auth 403 for all pods | vault-auth token deleted by prune | High |
| Phase 4 | Complete cluster outage | Prune deleted all HelmReleases on rename | CATASTROPHIC |

---

## Key Lessons

1. `prune: true` + Kustomization rename = mass deletion. Always disable prune before rename.
2. HelmRelease deletion = Helm uninstall = all pods gone. Not just the CR — everything.
3. healthCheck on a prunable resource = potential deadlock. Design healthChecks carefully.
4. K8s 1.24+ does not auto-create SA token secrets. Declare them explicitly in Git.
5. Anything needing vault injection belongs in `apps/`, never in `infrastructure/`.
6. One structural change at a time. Never rename + restructure + split simultaneously.

---

## Important Distinction — What dependsOn Does NOT Protect Against

`dependsOn` is a **Flux-level concept** — it only controls reconciliation order when
Flux is applying manifests. It has zero effect on runtime pod restarts.

| Scenario | dependsOn helps? |
|---|---|
| Fresh cluster start — Flux reconciling everything | ✅ Yes — apps waits for infrastructure READY |
| Power outage recovery — Flux reapplying all manifests | ✅ Yes — same ordering enforced |
| Running pod deleted manually or crashes | ❌ No — Kubernetes reschedules immediately |
| Worker node dies, pods reschedule to other nodes | ❌ No — Kubernetes scheduler, Flux not involved |

**Proven by TS-K8S-022 DR test (2026-04-11):**

Simultaneous delete of vault-agent-injector + wordpress pods:
```bash
kubectl delete pod -n vault -l app.kubernetes.io/name=vault-agent-injector &
kubectl delete pod -n apps -l app=wordpress
```

Result:
```
WordPress pods: Running 1/1  ← sidecar NOT injected
                              ← dependsOn completely bypassed
                              ← Kubernetes scheduled directly, no Flux involved
```

WordPress error:
```
mysqli_real_connect(): (HY000/1045): Access denied for user 'wordpress'
Error establishing a database connection
```

**What actually protects at runtime — vault-agent-injector HA:**

`dependsOn` protects deploy order. Runtime protection requires the injector
to never have a gap in availability. Fix applied in TS-K8S-022:

```yaml
# vault HelmRelease
injector:
  replicas: 2
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchLabels:
              app.kubernetes.io/name: vault-agent-injector
          topologyKey: kubernetes.io/hostname
```

With 2 replicas spread across masters:
```
Replica A → master1
Replica B → master2
       ↓
master1 crashes or injector pod dies
       ↓
Replica B still serving webhook immediately
       ↓
WordPress pods always get sidecar injected ✅
```

**Summary — two different problems, two different fixes:**

| Problem | Fix |
|---|---|
| Apps deploy before vault ready on cluster start | `dependsOn` + `healthCheck` in Flux |
| Apps restart without vault sidecar at runtime | `replicas: 2` + `podAntiAffinity` on injector |

Refrence to: 
  1. troubleshooting/kubernetes/22-worker-node-failure-cascading-pod-failures.md 
  2. disaster-recovery/task-1-pod-kill/RESULTS.md
  3. kubernetes/docs/flux_restructuring_operation_guide.md