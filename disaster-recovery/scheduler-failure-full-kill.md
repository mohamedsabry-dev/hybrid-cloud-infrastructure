DR Test: Scheduler Failure — Single Node → Full Kill → Restore
Date: 2026-05-01
Result: PASS
_____________________________________________________________________

[Info]
Domain: Control Plane — Scheduling Layer
Environment: PROD — 3 masters (kubeadm, static pods), 3 workers
Triggered by: Manual — planned DR test series, scheduler scenarios 1a/1b/1c

_____________________________________________________________________

[Planned Scope]

Goal: kill the scheduler progressively — one node, two nodes, all three —
and watch what happens to pod placement and the rest of the control plane.

The scheduler is the component that decides WHERE pods run. My theory going
in: without it, pods get created but stay Pending forever. Everything else
should keep working — apiserver, etcd, controllers all independent. Pods
just have nowhere to go.

Three-phase test:
  Phase 1a: kill leader scheduler on 1 master — HA should cover this
  Phase 1b: kill second scheduler — down to 1, still enough?
  Phase 1c: kill the last one — total scheduling death, then restore

What I expected to see:
  - Loki logs from apiserver complaining about missing scheduler
  - FailedScheduling events on pods created during outage
  - Some kind of cascade signal between components
  - Alertmanager firing when schedulers drop below threshold
  - Clear evidence trail across all 5 monitoring sources

What I actually found was very different from all of that.

Components expected to be affected:
  - New pod scheduling — stuck Pending
  - Deployments — rollouts won't progress
  - DaemonSets — unaffected (already placed)
  - Existing running pods — unaffected (already scheduled)

_____________________________________________________________________

[Observation Setup — 7 tabs]

Before touching anything, opened parallel monitoring:

1. Proxmox prod dashboard
2. Grafana scheduler dashboard (Up count, scheduling rate)
3. Loki: {namespace="kube-system", pod=~"kube-scheduler.*"}
4. Loki: {namespace="kube-system", pod=~"kube-controller.*"}
5. Loki: {namespace="kube-system", pod=~"kube-apiserver.*"}
6. Loki: {namespace="kube-system", pod=~"etcd.*"}
7. Alertmanager: http://alertmanager-prod.lab.local/#/alerts
   (3 etcd false alarms from TS-K8S-039 already present — ignored)

Note: during the test I deployed Kubernetes Event Exporter to bridge
a gap I discovered (explained in findings). So the later phases had
a 6th source: {job="kube-events"} in Loki.

_____________________________________________________________________

[Pre-State]

Identified current leader before starting:
  {namespace="kube-system", pod=~"kube-scheduler.*"} |= "leader"

  2026-05-01 11:55:44.823 leaderelection.go:272]
  "Successfully acquired lease" lock="kube-system/kube-scheduler"
  >> Leader: kube-scheduler-k8s-master3.lab.local

All 3 schedulers running. Grafana: Up: 3. Cluster healthy.

_____________________________________________________________________

[Test 1a — Kill leader scheduler (master3), 2 remain]

Action:
  ssh k8s-master3
  mv /etc/kubernetes/manifests/kube-scheduler.yaml /root/kube-scheduler.yaml.bak

What happened:
  Leader election — instant. Master2 picked up the lease:
  2026-05-01 14:51:18.537 leaderelection.go:272]
  "Successfully acquired lease" >> kube-scheduler-k8s-master2.lab.local

  Grafana: Up: 3 → Up: 2. That's the only visible signal.

What I expected vs what I got:
  Expected: apiserver logs about a disconnected watcher, maybe etcd
  noticing a lease change, controller-manager reacting somehow.

  Got: absolute silence from every other component. Controller-manager,
  apiserver, etcd — all quiet. Not a single log line about the scheduler
  dying. I checked all 4 Loki tabs multiple times thinking my queries
  were wrong. They weren't.

  At --v=0 (default verbosity), k8s only logs errors and state changes.
  A clean watch disconnect isn't an error. There's no "hey scheduler
  disconnected" message at any verbosity below --v=4 — and --v=4 is a
  firehose nobody runs in production.

Pod creation test:
  [root@k8s-master1 ~]# kubectl run test-sched-1a --image=nginx
  pod/test-sched-1a created

  NAME            READY   STATUS    RESTARTS   AGE
  test-sched-1a   1/1     Running   0          15s

  Events:
  25s  Normal  Scheduled  Successfully assigned default/test-sched-1a to k8s-worker3.lab.local
  24s  Normal  Pulling    Pulling image "nginx"
  11s  Normal  Pulled     Successfully pulled image "nginx" in 12.991s
  11s  Normal  Created    Container created
  11s  Normal  Started    Container started

What this tells me:
  HA works perfectly — single scheduler death is a non-event. The only
  place it registered was the Grafana metric counter. If I wasn't watching
  that dashboard, I'd have no idea a scheduler died.

_____________________________________________________________________

[Observability Gap — discovered mid-test]

After the 1a pod test, I checked all 4 Loki queries to see which component
logged about the pod creation. None of them did. Zero.

I expected at least the scheduler to log "assigned pod X to node Y" — that's
what I remembered seeing in past debugging. But what I was remembering was
kubectl events, not Loki logs. Two completely different systems:

  kubectl events = Event objects stored in etcd via the API. The scheduler
  writes an Event saying "assigned pod to node." Queryable via kubectl.
  NOT captured by Loki/Promtail (they scrape container stdout, not API objects).

  Loki = container stdout/stderr. At --v=0, scheduler prints nothing during
  normal operation. Only startup and errors.

  Prometheus/Grafana = aggregate metrics. "X pods scheduled per second" but
  not "pod Y went to node Z."

So for individual resource-level events — what happened to THIS specific
pod — kubectl was the only source. The 5-tab monitoring setup had a blind
spot: none of them could show per-resource events in Grafana.

[Decision — pause DR, deploy event exporter]

This gap would cripple the rest of my DR tests. I need to see what happens
to individual resources during failures, not just aggregate metrics.

Two options:
  1. Increase verbosity to --v=2 on scheduler/controller-manager
     → gives API request logging (plumbing-level: who called what endpoint)
     → doesn't give operational events (pod scheduled, image pulled, killed)
     → requires static pod manifest edits + restarts

  2. Deploy Kubernetes Event Exporter → ships events to Loki
     → gives exactly what kubectl events shows
     → "FailedScheduling", "Killing", "Pulling" — the operational stuff
     → searchable from Grafana via {job="kube-events"}

Went with option 2. Delegated the deployment to AI while I stayed focused
on the DR test. Deployed to monitoring namespace on both dev and prod.
Confirmed working — Grafana query {job="kube-events"} returns events.

Will reverse-check the manifests after the DR test series to validate
what was deployed. Didn't want to break focus mid-test.

Verified with a second test pod (test-sched-2a):
  2026-05-01 15:45:46 "Successfully assigned default/test-sched-2a to
  k8s-worker3.lab.local" source: "default-scheduler" type: Normal

  2026-05-01 15:45:53 "Successfully pulled image \"nginx\" in 1.032s"
  source: "kubelet" type: Normal

Notes:
  - "default-scheduler" = component name, not leader identity. All
    scheduler instances report as "default-scheduler" — can't tell
    which master handled it from the event alone
  - nginx 1.032s vs 12.991s on first run = image cached on worker3
  - "source: kubelet" = kubelet on worker3 generated the pull event

Event chain for pod creation:
  1. scheduler → "assigned pod to worker3"    (source: default-scheduler)
  2. kubelet   → "pulled/verified image"      (source: kubelet)
  3. kubelet   → "created container"           (source: kubelet)
  4. kubelet   → "started container"           (source: kubelet)

_____________________________________________________________________

[Test 1b — Kill leader scheduler (master2), down to 1]

Why this test: push past comfortable HA. Only 1 scheduler will remain.
Killed the leader (master2) instead of the standby (master1) — forces
another leader election under pressure.

Important context: scheduler uses leader election (single active), NOT
quorum. Only 1 scheduler is ever doing work at a time. The other 2 are
standby, just watching the lease. No voting, no consensus. If the leader
dies, whoever grabs the lease first wins. Even with 1 scheduler alive,
scheduling works. 3 is for failover redundancy only.

This is different from etcd — etcd needs 2/3 for quorum (majority).
Scheduler and controller-manager are simpler: 1 is enough.

Action:
  ssh k8s-master2
  mv /etc/kubernetes/manifests/kube-scheduler.yaml /root/kube-scheduler.yaml.bak

What happened:
  Leader election to master1:
  2026-05-01 15:53:44.565 leaderelection.go:272]
  "Successfully acquired lease" >> kube-scheduler-k8s-master1.lab.local

  Grafana: Up: 2 → Up: 1.

Cross-component reactions (didn't see any of this in 1a):

  1. Controller-manager EndpointSlice sync error:
     2026-05-01 15:53:45.872 endpointslice_controller.go:361]
     "Error syncing endpoint slices for service, retrying"
     key="kube-system/kube-prometheus-stack-kube-scheduler"
     err="EndpointSlice informer cache is out of date"

     What's happening: Prometheus scrapes scheduler metrics through a
     Service (kube-prometheus-stack-kube-scheduler). That Service has
     an EndpointSlice listing the scheduler pod IPs. When the scheduler
     on master2 died, it lost an endpoint. Controller-manager's job is
     to update EndpointSlices for ALL Services — it saw a backing pod
     die and tried to remove master2's IP from the list. Hit a stale
     cache on first try (informer hadn't caught up), retried, succeeded.

     This is the first cross-component reaction in the test.
     Controller-manager didn't react because it cares about the scheduler —
     it just maintains EndpointSlices for every Service, and this Service
     happened to lose a backend. Same thing would happen if any pod behind
     any Service died.

  2. Readiness probe failure (from event exporter):
     15:53:54 Warning Unhealthy — Readiness probe failed:
     "dial tcp 127.0.0.1:10259: connect: connection refused"
     Pod/kube-scheduler-k8s-master2.lab.local

     15:53:47 Normal Killing — "Stopping container kube-scheduler"
     Pod/kube-scheduler-k8s-master2.lab.local

     Kill came BEFORE Unhealthy. Kubelet moved the manifest → container
     stops → port 10259 closes → readiness probe fires on its normal
     timer → connection refused → "Unhealthy." The probe isn't smart
     enough to know the container is being intentionally killed. It just
     runs on schedule and catches the shutdown in progress.

     In a real liveness failure, the order is reversed: probe fails first,
     THEN kubelet kills. The ordering tells you the cause.

  3. Event exporter value proven:
     2 of these 3 signals were only visible through events (Killing and
     Unhealthy). Only the EndpointSlice cache error showed in controller-
     manager's own Loki logs. Without the event exporter deployed 30
     minutes ago, I'd have missed 2 out of 3 signals.

What I expected vs what I got:
  Expected: maybe some apiserver reaction now that we're down to 1.
  Got: apiserver still completely silent. Only the controller-manager
  reacted, and only because of the EndpointSlice — not because it
  cares about scheduling.

_____________________________________________________________________

[Test 1c — Kill last scheduler (master1), full outage]

Why this test: confirm total scheduling death. See what breaks, what
stays silent, and how recovery works.

Action:
  ssh k8s-master1
  mv /etc/kubernetes/manifests/kube-scheduler.yaml /root/kube-scheduler.yaml.bak

Scheduler logs — graceful termination sequence:
  16:05:54 Stopped listening on [::]:10259
  16:05:54 Shutting down DynamicServingCertificateController
  16:05:54 Shutting down controller client-ca
  16:05:55 E event.go:464] "Unable to record event (will not retry!)"
           err="broadcaster already stopped"
  16:05:55 "Requested to terminate, exiting"

  That last error is the scheduler trying to record its own death event
  but the event broadcaster already shut down. It dies mid-sentence.

Grafana scheduler dashboard: "No data"

Pod creation test:
  [root@k8s-master1 ~]# kubectl run test-sched-1c --image=nginx
  pod/test-sched-1c created

  NAME            READY   STATUS    RESTARTS   AGE
  test-sched-1c   0/1     Pending   0          12s

  kubectl describe pod test-sched-1c | tail
  Events:          <none>

  kubectl get pod test-sched-1c -o jsonpath='{.status.phase}'
  Pending

  kubectl get pod test-sched-1c -o jsonpath='{.spec.nodeName}'
  (empty)

What I expected vs what I got:
  Expected: FailedScheduling events on the pod. Some kind of error from
  apiserver saying "no scheduler available." Maybe a warning from etcd
  about an unfinished workflow. Alertmanager firing immediately.

  Got: THE QUIETEST FAILURE IN KUBERNETES. Literally nothing. No events
  (scheduler creates FailedScheduling events — no scheduler = no events
  at all). Nobody tried and failed. Nobody tried. Period.

  - Loki scheduler: dead, obviously
  - Loki controller-manager: silent
  - Loki apiserver: silent — stored the pod, doesn't care it has no node
  - Loki etcd: silent — just saved the object
  - Event exporter: nothing
  - kubectl describe: Events: <none>

  The only ways to detect this:
  - kubectl get pods and notice Pending status
  - Grafana scheduler dashboard showing "No data" (but that could look
    like a dashboard bug, not an outage)

etcd direct verification:
  I wanted to see what the pod looks like inside etcd with no scheduler.

  # Pod that was scheduled (test 1a):
  etcdctl get /registry/pods/default/test-sched-1a --print-value-only \
    | strings | grep -i "worker\|Pending\|Running"
  >> k8s-worker3.lab.localX
  >> Running

  # Pod with no scheduler (test 1c):
  etcdctl get /registry/pods/default/test-sched-1c --print-value-only \
    | strings | grep -i "worker\|Pending\|Running"
  >> Pending

  No nodeName. The pod just sits in etcd with an empty nodeName field
  forever. Apiserver stored it, etcd saved it, and the story ends there.

Signal flow — why nobody complains:
  kubectl run → apiserver → writes pod to etcd (nodeName: empty)
                    ↓
          scheduler WATCHES apiserver for pods with empty nodeName
                    ↓ (scheduler missing — nothing happens)
          kubelet WATCHES apiserver for pods assigned to its node
                    ↓ (never triggered — no node assigned)

  Pull-based architecture. Every component watches independently. Nobody
  pushes to anyone. If the watcher is missing, the upstream doesn't know
  or care. No timeout, no error, no retry. Just a pod sitting in etcd
  with an empty nodeName forever.

Alertmanager — email did arrive (delayed):
  16:22 (email) — [FIRING:1] KubeSchedulerDown
    severity: critical
    description: "KubeScheduler has disappeared from Prometheus target discovery."
    job: kube-scheduler
    prometheus: monitoring/kube-prometheus-stack-prometheus

  So there IS an alert — KubeSchedulerDown fired about 17 minutes after
  the last scheduler was killed (last kill at ~16:05, email at 16:22).
  The delay is the Prometheus scrape interval + alerting evaluation cycle +
  for duration on the rule. It's not instant, but it exists.

  16:27 (email) — [RESOLVED] KubeSchedulerDown
    Auto-resolved after scheduler restore.

_____________________________________________________________________

[Controller-Manager Independence — unexpected finding]

While all schedulers were down, I noticed the event exporter showing
WordPress HPA activity:

  16:22:06 replicaset-controller SuccessfulCreate
  "Created pod: wordpress-6c8c669587-vf6zw"

  16:22:13 replicaset-controller SuccessfulDelete
  "Deleted pod: wordpress-6c8c669587-vf6zw"

WordPress has an HPA that's been bouncing pods due to a memory metric
threshold I haven't tuned yet. The HPA + controller-manager kept creating
and deleting pods the entire time schedulers were down.

What I expected: controller-manager needs the scheduler to create pods
for a Deployment. I thought they work together — scheduler decides
placement, controller-manager manages desired state.

What's actually happening: controller-manager creates/deletes pod OBJECTS
through apiserver. That's its job — maintain desired replica count. The
scheduler's job is separate — assign those pods to nodes. Controller
doesn't check if the scheduler exists. Those HPA-created pods would've
been stuck Pending (like test-sched-1c) but the controller kept doing
its job regardless.

The components are truly independent. They don't check if each other
exists. They just watch their own domain through the apiserver and act.

_____________________________________________________________________

[Restore — master1 scheduler first]

Action:
  mv /root/kube-scheduler.yaml.bak /etc/kubernetes/manifests/kube-scheduler.yaml

  2026-05-01 16:25:43 scheduler acquired lease (master1 — only one alive)
  2026-05-01 16:25:55 test-sched-1c assigned to worker3

  12 seconds from scheduler up → Pending pod scheduled. Automatic. No
  manual intervention needed. Scheduler came online, found the Pending
  pod in its watch queue, assigned it.

  WordPress HPA backlog also cleared:
  16:27:19 wordpress-6c8c669587-67mbb assigned to worker3

  Flux reconciliation continued normally during the entire test:
  16:23:35 Kustomization/flux-system ReconciliationSucceeded (529ms)

Recovery timeline:
  T+0:00   16:05  last scheduler killed
  T+17:00  16:22  KubeSchedulerDown alert email received
  T+20:00  16:25  master1 scheduler restored, lease acquired
  T+20:12  16:25  test-sched-1c scheduled (was Pending ~20 min)
  T+22:00  16:27  wordpress backlog cleared
  T+22:00  16:27  KubeSchedulerDown resolved email received

Note: master2 and master3 schedulers still need restoring after the test.

_____________________________________________________________________

[Findings]

1. Scheduler uses leader election, NOT quorum.
   Only 1 scheduler is ever active. The other 2 are standby watching
   the lease. No voting, no consensus. 1 scheduler is enough for full
   cluster operation. 3 is purely for failover. This is different from
   etcd (needs 2/3 majority).

2. Single scheduler kill is invisible.
   The ONLY signal was Grafana metrics dropping from Up: 3 to Up: 2.
   No logs from apiserver, etcd, or controller-manager. No events, no
   alerts. At default verbosity (--v=0), a clean watcher disconnect
   isn't logged.

3. Full scheduler kill is the quietest failure in k8s.
   Pods silently pile up as Pending with Events: <none>. No component
   complains. No FailedScheduling events (the scheduler creates those —
   no scheduler = no events). The pod sits in etcd with empty nodeName
   forever. Pull-based architecture: if the watcher is missing, nobody
   upstream knows or cares.

4. Alertmanager DID fire — with delay.
   KubeSchedulerDown email arrived ~17 minutes after last kill. It exists
   in kube-prometheus-stack by default. Not instant (scrape interval +
   evaluation + for duration), but it catches total scheduler loss. Auto-
   resolved after restore.

5. Controller-manager is fully independent of scheduler.
   WordPress HPA kept creating/deleting pods during full scheduler outage.
   Controllers manage desired state (pod objects), scheduler manages
   placement (node assignment). They don't check if each other exists.
   This confirms loose coupling — a key architecture property.

6. Recovery is instant and automatic.
   Restoring 1 scheduler was enough. It found all Pending pods and
   scheduled them within 12 seconds. No manual queue drain, no restart
   needed. The backlog (test pods + HPA wordpress pods) all cleared
   automatically.

7. Event exporter was critical for this test.
   Deployed mid-test after discovering the observation gap. Caught the
   EndpointSlice sync error and readiness probe signals in test 1b that
   Loki component logs missed entirely. kubectl events → Loki via event
   exporter is now the 6th monitoring source for all future DR tests.

8. etcd stores the truth.
   Direct etcd access confirmed what kubectl showed: test-sched-1a had
   nodeName=worker3/Running, test-sched-1c had no nodeName/Pending.
   etcd is the ground truth — everything else is a derived view.

_____________________________________________________________________

[Fixes Applied]

| Fix | Reason |
|-----|--------|
| Event Exporter deployed (dev + prod) | kubectl events had no path to Grafana — blind spot in all 5 monitoring sources |

_____________________________________________________________________

[Open Items]

- Consider PrometheusRule: alert when pending pods > 0 for X minutes
  (catches the silent scheduling gap before KubeSchedulerDown fires)
- Event exporter manifests need reverse-check (delegated during test)
- Verbosity increase to --v=2 still worth considering for scheduler
  and controller-manager (deferred — not needed for DR tests)

_____________________________________________________________________

[Planned Next]

- Controller-manager down — same approach (scenario 2a from drafts)
- Controller-manager down mid-Flux reconciliation (scenario 2b)
- Compare scheduler behavior vs controller-manager behavior under
  same progressive kill pattern

_____________________________________________________________________

[References]

- disaster-recovery/drafts/raw-data — full investigation notes with
  timestamps, raw commands, and conversation context
- disaster-recovery/drafts/draft-scheduler-down — original test plan
- kubernetes/dev/deployments/apps/event-exporter/ — exporter manifests
- troubleshooting/kubernetes/39-kube-system-targetdown-false-positives.md
  — related monitoring fix (kube-proxy, etcd metrics)
