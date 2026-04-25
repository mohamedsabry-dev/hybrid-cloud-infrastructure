# TS-K8S-049 | 2026-04-23 | RESOLVED | INCIDENT
# Trigger: Git history rewrite force-pushed from stale local → Flux prune cascade
_____________________________________________________________________

[Info]
Domain: Kubernetes / FluxCD / Git operations
Sub-techs: Flux GitRepository, Kustomization prune, kustomize-controller,
           source-controller, git filter-repo, force-push, CoreDNS ConfigMap,
           CSI NFS driver registration, Flux self-lock via cluster DNS
Environment: PROD k8s-prod cluster | full application outage
Re-opened: No

_____________________________________________________________________

[Issue Description]
Opened prod 2026-04-23 morning. Apps down: wordpress, mariadb, grafana,
remediation all Unknown. CoreDNS 0/2 Unknown. Flux Kustomizations unable
to reconcile — source-controller unreachable because cluster DNS was dead.
Cluster had been healthy at last observation 2 days prior.

Actual impact at discovery:
  apps/wordpress (3/3)         0 Running  — all Unknown
  database/mariadb (1/1)       0 Running  — Unknown
  monitoring/grafana (3/3)     0 Running  — all Unknown
  remediation (1/1)            0 Running  — Unknown
  kube-system/coredns (2/2)    0 Running  — FailedMount on missing cm
  Flux reconciliation          Self-locked (source-controller unreachable)

Expected impact had Flux not self-locked: full cluster prune. Containment
was incidental — CoreDNS went down early enough in the prune that
kustomize-controller could no longer resolve source-controller, freezing
before any more resources were deleted.

_____________________________________________________________________

[Analysis]

# Initial Check Notes:

No Proxmox alarms. Vault HCP active and unsealed. Host-level DNS works
(ping google.com returns). Suspect k8s. Checked kube-system first based on
impact scope.

Command:
  kubectl get pods -o wide -A

Output (key rows):
  kube-system  coredns-5b4b8c66cd-n77vv  0/1 Unknown  6   6d16h
  kube-system  coredns-5b4b8c66cd-vm2fj  0/1 Unknown  6   6d16h
  apps         wordpress-*               0/2 Unknown  18  9d
  database     mariadb-0                 0/2 Unknown  20  9d
  monitoring   grafana-*                 0/4 Unknown  37  9d
  remediation  remediation-*             0/2 Unknown  22  10d

Command:
  kubectl describe pod coredns-5b4b8c66cd-vm2fj -n kube-system

Output (events):
  Warning  FailedMount  6h22m (x394 over 19h)  kubelet
    MountVolume.SetUp failed for volume "config-volume"
    : configmap "coredns" not found

Command:
  kubectl get cm -n kube-system

Output:
  calico-config                                          4      27d
  extension-apiserver-authentication                     6      27d
  kube-apiserver-legacy-service-account-token-tracking   1      27d
  kube-proxy                                             2      27d
  kube-root-ca.crt                                       1      27d
  kubeadm-config                                         1      27d
  kubelet-config                                         1      27d
  (coredns ConfigMap GONE)

Command (dev compare):
  KUBECONFIG=~/.kube/config-dev kubectl get cm -n kube-system

Output:
  coredns  1  27d    ← present in dev, missing in prod only

Command:
  flux get kustomization

Output:
  flux-system    prod@sha1:a1cfc79c  False  False
    failed to download archive: dial tcp:
    lookup source-controller.flux-system.svc.cluster.local. on 10.96.0.10:53:
    read udp 10.245.62.23:52497->10.96.0.10:53: read: connection refused
  infrastructure prod@sha1:a1cfc79c  False  Unknown  Reconciliation in progress
  apps           prod@sha1:474faf0f  False  False
    dependency 'flux-system/infrastructure' is not ready

Command (tried to find who deleted the cm):
  kubectl logs -n flux-system deploy/kustomize-controller --since=72h | grep coredns
  flux logs | grep coredns
  sudo journalctl -u kubelet --since '3 days ago' | grep -i coredns

Output: all empty. kustomize-controller had 17 restarts — anything older than
the most recent container is gone. Apiserver audit not enabled (kubeadm default).
Dead end from cluster logs.


# Suspected Root Cause

First pass — clear enough chain: coredns configmap missing → cluster DNS
down → Flux can't reach its own source-controller → reconciliation frozen.
Same DNS outage explains CSI NFS "driver not registered" events I saw on
wordpress/mariadb describes, and everything downstream going Unknown.

But the real question is why the configmap is gone. I didn't delete it
manually. No trace in kubelet, Flux, or kustomize-controller logs within
the retention window. Audit logs not enabled. Needed to look at Git side.


# More Checks Notes:

Traced back to a git history-rewrite audit I ran 2 days prior
(evening 2026-04-21) to scrub leaked secrets from commit history. At the
time the operation looked clean — Flux reconciled normally right after,
env looked healthy. I didn't re-observe after cluster reboot.

What actually happened: the filter-repo / secret-scrub ran on my local
checkout of prod, and my local prod branch was weeks behind origin. I
hadn't pulled in a long time and hadn't merged dev→prod since. The
rewrite produced all-new hashes for the commits my local knew about —
but the ~70 commits that existed only on origin were never part of the
rewrite because filter-repo never saw them.

Then the force-push replaced origin/prod with my stale-but-rewritten tree.
Every commit that had existed only on origin became orphaned. GitHub keeps
them in reflog ~90 days but as far as any ref goes they're gone.

The `coredns` ConfigMap is defined in:
  kubernetes/prod/deployments/infrastructure/coredns/coredns-custom.yaml
(filename says "-custom" but `metadata.name: coredns` — this IS the main
CoreDNS ConfigMap, Flux-managed, not kubeadm-default).

That file was added to Git in one of the ~70 commits that got erased by
the force-push. After the push, the file still existed in my local working
tree (so I could re-apply it manually later) but was not in the pushed
history.

Flux's next reconcile post-push pulled the rolled-back ref, saw
`coredns` ConfigMap as "no longer in desired state", and pruned it. Same
mechanism would have pruned every other resource added in the erased 70
commits — but the prune cascade tripped over its own feet when CoreDNS
went down, killing cluster DNS and breaking kustomize-controller's ability
to reach source-controller.


# Suspected Solution

Stuck in a loop: need Flux reconciled to restore state, but Flux can't
reconcile because cluster DNS is dead, and DNS is dead because coredns
configmap is gone. Need to break the loop manually, and CRITICALLY I can
NOT let Flux reconcile the stale ref — if DNS comes back with the bad
ref still in origin, Flux will prune everything else.

My options were:
  1. Fix in-place: manually apply coredns cm + suspend Flux + push PR
     with all 70 missing commits + reconcile against corrected ref
  2. Stop Flux, stop etcd (doesn't fix anything, just prevents further damage)
  3. Full etcd restore from 3-day-old S3 backup
  3b. Restore master VM backups from 3 days

I rejected 2/3/3b. Etcd restore is overkill — the actual problem is one
missing ConfigMap. Restoring means losing 3 days of real state to fix one
resource, and the broken Git ref is still there so it would happen again
on next reconcile. Option 1 is the smallest fix: one kubectl apply + one
git push. Going with option 1.

Ordering matters:
  1. Suspend Flux FIRST. Any kustomization still enabled will prune more
     the moment DNS returns.
  2. Apply coredns cm from local working tree (still has the file) →
     cluster DNS comes back → Flux can reach source-controller again.
  3. Push PR with the corrected history so origin/prod has all 70 commits.
  4. Force source-controller to refetch.
  5. Resume kustomizations in dependency order.
  6. Force-delete wedged pods where kubelet sandbox is stuck on the old
     failed mount — these won't self-heal.


# Test

Executed recovery in exact order:

  # 1. Freeze Flux before DNS returns
  flux suspend kustomization infrastructure
  flux suspend kustomization apps
  flux suspend kustomization flux-system

  # 2. Apply missing ConfigMap from local working tree
  kubectl apply -f kubernetes/prod/deployments/infrastructure/coredns/coredns-custom.yaml
  configmap/coredns created

  # 3. Restart CoreDNS to pick it up
  kubectl rollout restart deployment coredns -n kube-system

  # 4. Verify DNS up
  kubectl get pods -n kube-system -l k8s-app=kube-dns
  coredns-54b98fc47d-lzwbz  1/1  Running  0  5s
  coredns-54b98fc47d-n94zl  1/1  Running  0  5s

  # 5. Push PR to origin/prod with all missing commits
  # (latest commit hash after PR: de50358)

  # 6. Force source-controller to pull new ref
  flux reconcile source git flux-system
  fetched revision prod@sha1:de50358bde85fe0d80f8d4db3953845abb559573

  # 7. Resume + reconcile in dependency order
  flux resume kustomization flux-system
  flux resume kustomization infrastructure
  flux reconcile kustomization infrastructure --with-source
  flux resume kustomization apps
  flux reconcile kustomization apps --with-source

  # 8. Force-delete pods wedged in Unknown (kubelet sandbox stuck)
  kubectl delete pod -n apps -l app=wordpress --force
  kubectl delete pod -n database mariadb-0 --force
  kubectl delete pod -n monitoring -l app.kubernetes.io/name=grafana --force
  kubectl delete pod -n remediation -l app=remediation --force

Final state:
  apps/wordpress               3/3  Running  29s
  database/mariadb-0           2/2  Running  28s
  monitoring/grafana           4/4  Running  (transient 3/4 → 4/4)
  remediation                  2/2  Running  28s
  kube-system/coredns          2/2  Running  3m20s
  kube-system/csi-nfs-*        all fresh Running (re-reconciled by Flux)
  ingress-nginx                3/3  fresh Running (re-reconciled)
  vault-agent-injector         2/2  fresh Running (re-reconciled)
  flux kustomizations          all "True" — Applied revision prod@de50358b

Result: PASS — full cluster recovered. Total outage ~3 hours from first
observation to full-green state.

_____________________________________________________________________

[Final Root Cause]

Two-day-old git history-rewrite audit (secret scrub via filter-repo or
equivalent) was force-pushed to origin/prod from a local checkout that
was weeks behind origin. The rewrite only saw the commits that existed
locally; ~70 commits that existed only on origin were never part of it.
Force-push replaced origin/prod with the stale-but-rewritten tree,
orphaning the missing 70 commits.

Flux GitRepository fetched the rolled-back ref. kustomize-controller
with `prune: true` began deleting resources no longer in the desired
state. First casualty was the `coredns` ConfigMap (defined in a file
added in one of the erased commits). Cluster DNS died. kustomize-
controller could no longer resolve source-controller via cluster DNS and
self-locked before the prune cascade completed. Remaining HelmRelease-
managed resources (CSI, ingress, vault-injector) survived only because
the freeze happened before Flux got to them.

Downstream cascade:
  coredns deleted      → cluster DNS dead
  DNS dead             → Flux can't resolve source-controller
                       → CSI HelmRelease ArtifactFailed (can't pull chart)
                       → CSI driver not re-registered after restart
  No CSI driver        → apps with NFS PVCs fail to mount
  Failed volume mounts → kubelet sandbox wedged → pods stuck Unknown
  Flux frozen          → no further prune damage (lucky containment)

_____________________________________________________________________

[Final Solution]

Immediate recovery executed 2026-04-23 (see Test section for commands).

Permanent structural fixes (to prevent recurrence):

  1. NEVER run history rewrites on branches Flux tracks.
     Audits happen on a throwaway mirror clone. If origin history on a
     Flux-tracked branch must be replaced, do it from a fresh, fully-up-
     to-date clone with the pre-verification checklist below.

  2. Pre-rewrite verification checklist (mandatory before any force-push
     to a Flux-tracked branch):
       git fetch --all
       git log prod..origin/prod    # MUST be empty — if not, local is stale
       git log origin/prod..prod    # review outgoing commits
       git tag backup-pre-<op>-YYYY-MM-DD origin/prod
       git push origin backup-pre-<op>-YYYY-MM-DD

  3. Always `flux suspend` before any force-push to a Flux-tracked branch.
     Resume only after verifying origin ref is correct post-push.

  4. Push rewrites to a review branch first, diff, then replace:
       git push origin rewritten:audit-review-YYYY-MM-DD
       # review on GitHub against prod
       # only then: git push --force origin rewritten:prod

  5. Prefer rotation over scrubbing for leaked secrets.
     Once a secret hits a shared remote it is compromised. Scrubbing is
     cosmetic. Rotate at the source (AWS key, Vault token), commit a
     revert forward, move on. Scrubbing can cause exactly this kind of outage.

  6. Enable GitHub branch protection on prod — require status checks,
     block force-push without explicit override. This alone would have
     prevented the incident.

  7. Consider enabling apiserver audit logging for future forensic
     trails. Without it, the deletion moment was only recoverable from
     kubelet FailedMount timestamps (approximate, not definitive).

  8. Consider `prune: false` on foundation kustomizations (coredns,
     csi-driver-nfs, flux-system itself) so a bad ref cannot delete
     cluster essentials. Trade-off: genuine removals require manual
     cleanup. Acceptable for foundations.

Verified: Yes

_____________________________________________________________________

[Risk Level] CRITICAL (incident) / LOW (after fixes + checklist applied)

_____________________________________________________________________

[References]
- troubleshooting/kubernetes/19-flux-kustomization-restructure-cascade-failure.md
  (related theme: prune cascade from a mis-operated Flux refactor)
- troubleshooting/kubernetes/44-coredns-ha-masters.md
- kubernetes/prod/deployments/infrastructure/coredns/coredns-custom.yaml
  (the file whose disappearance triggered the cascade)

_____________________________________________________________________

[Draft Notes]

Notes:
  1. Force-push + stale local = silent data loss on origin. The ONLY
     defense is `git log local..origin` before the force-push.
  2. filter-repo's default behavior (removes origin remote, aggressive
     gc) amplifies the damage — it assumes you know what you're doing.
  3. On a Flux-tracked branch, rolling history backward is structurally
     equivalent to deleting every resource added in the erased commits.
     Flux can't distinguish "intentionally removed" from "accidentally
     orphaned by a bad push."
  4. `prune: true` is dangerous on foundation resources. DNS, CSI,
     Flux itself — these should either have prune disabled or be in a
     separate non-pruning kustomization.
  5. The containment was luck — CoreDNS died early enough in the prune
     that Flux lost DNS before it could delete more. Different prune
     order and everything would have been gone.
  6. Secret scrubbing is almost always the wrong response to a leak.
     Rotate, don't rewrite. The only exception is an unshared repo that
     has never left a single machine.

_____________________________________________________________________
IMPORTANT — Why etcd restore was rejected
_____________________________________________________________________

S3 etcd backups existed from 3 days prior (pre-incident). Could have
rolled cluster state back to before the bad push. Rejected for three
reasons:

  1. Scope mismatch. Cluster's actual problem was ONE missing ConfigMap.
     Restoring etcd rolls back 3 days of legitimate state (PVC bindings,
     pod UIDs, cronjob schedules, secret rotations) to fix one resource.

  2. Doesn't fix the Git root cause. On next Flux reconcile post-restore,
     the stale remote ref would re-prune the restored ConfigMap. Restore
     without pushing the Git fix = back to square one in minutes.

  3. Too much risk for the problem size. Etcd restore requires all-master
     downtime and careful consistency handling. The actual fix is one
     kubectl apply + one PR. The recovery shouldn't be bigger than the
     incident.

Restore-from-backup is the right tool when cluster state is corrupt or
unrecoverable. Here, state was fine — Git was broken. Fix Git, apply
one ConfigMap, move on.
