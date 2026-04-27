# TS-K8S-052 | 2026-04-27 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / Vault Agent Injector / Proxmox / Container Runtime
Sub-techs: vault-agent-init, containerd overlayfs page faults, Proxmox disk
           bandwidth throttle (scsi0), Go binary cold-load,
           crictl inspect, kubelet journal, Vault audit logs, tcpdump
Environment: DEV k8s cluster | 3 masters + 3 workers | Proxmox VMs
Severity: MEDIUM (boot-time only, self-resolves)
Discovered during: Pod lifecycle learning session — remediation pod Unknown for ~5 min after cold boot
Related: TS-K8S-053 (CoreDNS boot delay — found during same investigation),
         TS-K8S-033 (Vault Agent DNS failure — similar symptoms, different root cause),
         TS-PVE-017 (Proxmox disk throttle config — source of the bad limits)
Re-opened: No

_____________________________________________________________________

[Issue Description]
After every cluster cold boot, the remediation pod sat in Unknown/Init
status for ~5 minutes before becoming Running. Same pattern on
alertmanager. Both are vault-injected pods on master nodes.

The vault-agent-init container was "Started" according to kubelet events
but produced zero logs, zero network traffic, and zero output for the
entire 5-minute window. Then suddenly completed in under a second and
the pod went Running normally.

Non-vault pods on the same nodes recovered in 30-60 seconds. WordPress
(vault-injected but on workers) recovered in ~9 seconds. The delay was
specific to vault-agent-init on master nodes during cold boot.

_____________________________________________________________________

[Analysis]

# How I found it

Started a k8s learning session focused on pod lifecycle monitoring.
During env startup after a routine reboot, noticed remediation stuck
in Unknown for ~5 minutes:

```
[root@k8s-master1 ~]# kubectl get pods -A -o wide | grep -E "remediation|vault"
remediation     remediation-774679955-fbtg6                                 0/2     Unknown     6                32h
     10.245.14.153    k8s-master2.lab.local   <none>           <none>
vault           vault-agent-injector-778c55db9b-9mzwq                       1/1     Running     4 (5m44s ago)    33h
     10.245.14.151    k8s-master2.lab.local   <none>           <none>
vault           vault-agent-injector-778c55db9b-kssq8                       1/1     Running     4 (5m44s ago)    33h
     10.245.25.196    k8s-master3.lab.local   <none>           <none>
```

Remediation 0/2 Unknown with 6 restarts. Vault injectors already Running.
Pod on master2. Vault on master2 and master3 — already up.
Vault up, kubelet up, but remediation stuck in its init container.

# Describe pod events

```
[root@k8s-master1 ~]# kubectl describe pod remediation-774679955-fbtg6 -n remediation | tail
Events:
  Type    Reason          Age                    From     Message
  ----    ------          ----                   ----     -------
  Normal  SandboxChanged  4m28s (x2 over 5m24s)  kubelet  Pod sandbox changed, it will be killed and re-created.
  Normal  Pulled          4m27s                  kubelet  spec.initContainers{vault-agent-init}: Container image
"hashicorp/vault:1.21.2" already present on machine and can be accessed by the pod
  Normal  Created         4m27s                  kubelet  spec.initContainers{vault-agent-init}: Container created
  Normal  Started         4m27s                  kubelet  spec.initContainers{vault-agent-init}: Container started
```

SandboxChanged = kubelet sees old sandbox gone after restart → recreates.
vault-agent-init started 4m27s ago, pod still Unknown — init container still running.

# Events timeline — the 5-minute gap

```
[root@k8s-master1 ~]# kubectl events -n remediation
LAST SEEN               TYPE     REASON           OBJECT                            MESSAGE
5m37s (x2 over 6m33s)   Normal   SandboxChanged   Pod/remediation-774679955-fbtg6   Pod sandbox changed...
5m36s                   Normal   Pulled           Pod/remediation-774679955-fbtg6   Container image
"hashicorp/vault:1.21.2" already present on machine
5m36s                   Normal   Created          Pod/remediation-774679955-fbtg6   Container created
5m36s                   Normal   Started          Pod/remediation-774679955-fbtg6   Container started
35s                     Normal   Pulling          Pod/remediation-774679955-fbtg6   Pulling image
"ghcr.io/mohamedsabry-dev/remediation:latest"
34s                     Normal   Pulled           Pod/remediation-774679955-fbtg6   Successfully pulled image in 775ms
34s                     Normal   Created          Pod/remediation-774679955-fbtg6   Container created
34s                     Normal   Started          Pod/remediation-774679955-fbtg6   Container started
34s                     Normal   Pulled           Pod/remediation-774679955-fbtg6   Container image
"hashicorp/vault:1.21.2" already present on machine
34s                     Normal   Created          Pod/remediation-774679955-fbtg6   Container created
34s                     Normal   Started          Pod/remediation-774679955-fbtg6   Container started
```

~5 minute gap between vault-agent-init Started (5m36s) and main container
Pulling (35s). Restart count went from 6 to 8 during this boot cycle.

# vault-agent-init is fast — proved it

My sequence has Vault unseal before k8s nodes boot even. Checked vault-agent-init
logs — auth + secret read + template render took 22 seconds total:

```
==> Vault Agent started! Log data will stream in below:
2026-04-26T08:03:28.641Z [INFO]  agent.sink.file: creating file sink
2026-04-26T08:03:30.221Z [INFO]  agent.sink.file: file sink configured: path=/home/vault/.vault-token
2026-04-26T08:03:37.626Z [INFO]  agent.exec.server: starting exec server
2026-04-26T08:03:39.047Z [INFO]  agent.exec.server: no env templates or exec config, exiting
2026-04-26T08:03:39.047Z [INFO]  agent.auth.handler: starting auth handler
2026-04-26T08:03:37.984Z [INFO]  agent.template.server: starting template server
2026-04-26T08:03:41.195Z [INFO]  agent.auth.handler: authenticating
2026-04-26T08:03:44.656Z [INFO]  agent.auth.handler: authentication successful, sending token to sinks
2026-04-26T08:03:49.716Z [INFO]  agent: (runner) rendered "(dynamic)" => "/vault/secrets/proxmox-creds"
2026-04-26T08:03:49.716Z [INFO]  agent: (runner) stopping
2026-04-26T08:03:50.393Z [INFO]  agent.auth.handler: auth handler stopped
```

vault-agent-init took ~22 seconds (08:03:28 → 08:03:50). Auth sub-second.
So vault-agent-init itself NOT the bottleneck. The 5-min delay somewhere else.

# Kubelet status + boot timing

```
[root@k8s-master1 ~]# systemctl status kubelet
● kubelet.service - kubelet: The Kubernetes Node Agent
     Active: active (running) since Sun 2026-04-26 10:57:04 EEST; 33min ago
   Main PID: 1931 (kubelet)
```

Kubelet journal — first attempt failed, containerd.sock not ready yet:

```
Apr 26 10:56:50 k8s-master1.lab.local systemd[1]: Started kubelet.service
Apr 26 10:56:54 k8s-master1.lab.local kubelet[1169]: E0426 10:56:54.480602 run.go:72] "command failed"
  err="failed to run Kubelet: validate service connection: validate CRI v1 runtime API for endpoint
  \"unix:///var/run/containerd/containerd.sock\": rpc error: code = Unavailable desc = connection error:
  desc = \"transport: Error while dialing: dial unix /var/run/containerd/containerd.sock:
  connect: no such file or directory\""
Apr 26 10:56:54 k8s-master1.lab.local systemd[1]: kubelet.service: Failed with result 'exit-code'.
Apr 26 10:57:04 k8s-master1.lab.local systemd[1]: kubelet.service: Scheduled restart job
Apr 26 10:57:04 k8s-master1.lab.local systemd[1]: Started kubelet.service
```

First attempt failed — containerd.sock not ready. Restarted at 10:57:04 successfully.
Quite strange but ok, it succeeded after restart.

# Kubelet calico errors at boot

```
Apr 26 10:58:07 k8s-master1.lab.local kubelet[1931]: E0426 10:58:07.165643 log.go:32]
  "StopPodSandbox from runtime service failed" err="rpc error: code = Unknown desc = failed to destroy
  network for sandbox \"969c930ad3d008aac...\":
  plugin type=\"calico\" failed (delete): error getting ClusterInformation: Get
  \"https://[10.96.0.1]:443/apis/crd.projectcalico.org/v1/clusterinformations/default\":
  dial tcp 10.96.0.1:443: connect: connection refused"
```

Calico can't destroy old sandbox networks — API server not up yet.
Blocks sandbox cleanup until API comes up.

# Kube-system events — full cluster boot sequence

```
[root@k8s-master1 ~]# kubectl events kube-controller-manager-k8s-master2.lab.local -n kube-system
33m    Normal    SandboxChanged     Pod/kube-controller-manager-k8s-master2.lab.local  Pod sandbox changed...
33m    Normal    SandboxChanged     Pod/etcd-k8s-master1.lab.local                     Pod sandbox changed...
33m    Normal    SandboxChanged     Pod/kube-apiserver-k8s-master3.lab.local           Pod sandbox changed...
33m    Warning   Unhealthy          Pod/etcd-k8s-master3.lab.local    Startup probe failed: Get "http://127.0.0.1:2381/readyz": dial tcp 127.0.0.1:2381: connect: connection refused
33m    Warning   Unhealthy          Pod/kube-apiserver-k8s-master1.lab.local   Startup probe failed: TLS handshake timeout
33m    Warning   Unhealthy          Pod/kube-apiserver-k8s-master2.lab.local   Startup probe failed: connection reset by peer
33m    Warning   BackOff            Pod/kube-apiserver-k8s-master2.lab.local   Back-off restarting failed container
33m    Warning   BackOff            Pod/kube-apiserver-k8s-master3.lab.local   Back-off restarting failed container
32m    Normal    LeaderElection     Lease/kube-controller-manager   k8s-master1 became leader
32m    Normal    LeaderElection     Lease/kube-scheduler            k8s-master1 became leader
32m    Warning   Unhealthy          Pod/calico-node-zfslq   BIRD is not ready: BGP not established with 10.0.54.10,10.0.54.11,10.0.54.12
32m    Warning   Failed             Pod/calico-node-752w9   Error: services have not yet been read at least once, cannot construct envvars
31m    Warning   NodeNotReady       Pod/metrics-server-...  Node is not ready
31m    Warning   NodeNotReady       Pod/calico-node-gtg6l   Node is not ready
31m    Warning   NodeNotReady       Pod/calico-node-t9mf4   Node is not ready
30m    Normal    TaintManagerEviction  Pod/metrics-server-...   Cancelling deletion of Pod
30m    Normal    TaintManagerEviction  Pod/calico-kube-controllers-...  Cancelling deletion of Pod
30m    Normal    SandboxChanged     Pod/calico-node-t9mf4    Pod sandbox changed...  (workers coming up)
30m    Warning   Unhealthy          Pod/calico-node-t9mf4    BIRD not established with 10.0.54.12
29m    Normal    LeaderElection     Lease/external-resizer-nfs-csi-k8s-io   k8s-worker1 became leader
29m    Normal    LeaderElection     Lease/nfs-csi-k8s-io    became leader
```

Boot sequence: etcd → apiserver (BackOff!) → controller-manager (leader elect) →
calico BGP → workers come up (NodeNotReady → SandboxChanged → Running) →
leader elections for DaemonSets.

# Alertmanager — same pattern

```
[root@k8s-master1 ~]# kubectl get pods -A -o wide | grep -E "alertmanager|remediation"
monitoring      alertmanager-0                                              0/2     Unknown     10               40h
     10.245.25.203    k8s-master3.lab.local   <none>           <none>
remediation     remediation-774679955-fbtg6                                 0/2     Unknown     10               40h
     10.245.14.159    k8s-master2.lab.local   <none>           <none>
```

Both vault-injected pods on masters stuck in Unknown. Same pattern.
Is alertmanager also dependent on something? Its so strange. They become
normal once workers up.

```
[root@k8s-master1 ~]# kubectl get events -n monitoring
6m32s       Normal    SandboxChanged     pod/alertmanager-0          Pod sandbox changed...
6m32s       Normal    Started            pod/alertmanager-0          vault-agent-init: Container started
72s         Normal    Pulled             pod/alertmanager-0          alertmanager image already present
72s         Normal    Started            pod/alertmanager-0          Container started
8m31s       Warning   Unhealthy          pod/kube-state-metrics-...  Liveness probe failed: timeout exceeded
8m46s       Warning   Unhealthy          pod/kube-state-metrics-...  Liveness probe failed: 503
8m31s       Normal    Killing            pod/kube-state-metrics-...  Container failed liveness probe, will be restarted
```

alertmanager same ~5min gap. kube-state-metrics restarted from liveness
timeout during boot.

After workers came up, everything resolved:

```
[root@k8s-master1 ~]# kubectl get nodes
NAME                    STATUS   ROLES           AGE   VERSION
k8s-master1.lab.local   Ready    control-plane   30d   v1.35.3
k8s-master2.lab.local   Ready    control-plane   30d   v1.35.3
k8s-master3.lab.local   Ready    control-plane   30d   v1.35.3
k8s-worker1.lab.local   Ready    <none>          30d   v1.35.3
k8s-worker2.lab.local   Ready    <none>          30d   v1.35.3
k8s-worker3.lab.local   Ready    <none>          30d   v1.35.3

remediation     remediation-774679955-fbtg6   2/2   Running   12 (8m48s ago)   40h
```

# Full describe with two boot cycles

```
[root@k8s-master1 ~]# kubectl describe pod remediation-774679955-fbtg6 -n remediation | tail -15
Events:
# Boot cycle 1:
  Normal  SandboxChanged  53m (x2 over 54m)  kubelet  Pod sandbox changed...
  Normal  Started         53m                kubelet  vault-agent-init: Container started
  Normal  Pulling         48m                kubelet  Pulling image "ghcr.io/.../remediation:latest"
  Normal  Started         48m                kubelet  Container started
# Boot cycle 2 (Flux reconciliation triggered):
  Normal  SandboxChanged  38m (x2 over 39m)  kubelet  Pod sandbox changed...
  Normal  Started         38m                kubelet  vault-agent-init: Container started
  Normal  Pulling         33m                kubelet  Pulling image "ghcr.io/.../remediation:latest"
  Normal  Started         33m                kubelet  Container started
```

Both cycles: 5-minute gap between vault-agent-init Started and main container
Pulling. No hidden events in between. No crashes. Just silence for 5 minutes.

# Controller manager logs

```
[root@k8s-master1 ~]# kubectl logs kube-controller-manager-k8s-master2.lab.local -n kube-system | head -15
I0426 15:33:35.300175       1 serving.go:386] Generated self-signed cert in-memory
I0426 15:33:35.653225       1 controllermanager.go:189] "Starting" version="v1.35.3"
I0426 15:33:35.654256       1 dynamic_cafile_content.go:161] "Starting controller" name="request-header..."
I0426 15:33:35.654760       1 leaderelection.go:258] "Attempting to acquire leader lease..."
E0426 15:33:35.655124       1 leaderelection.go:452] "Error retrieving lease lock"
  err="Get \"https://10.0.51.11:6443/...\": dial tcp 10.0.51.11:6443: connect: connection refused"
E0426 15:33:44.543885       1 leaderelection.go:452] "Error retrieving lease lock"
  err="...net/http: request canceled while waiting for connection (Client.Timeout exceeded)"
I0426 15:34:03.154130       1 leaderelection.go:272] "Successfully acquired lease"
```

Controller manager: API refused at 15:33:35, succeeded at 15:34:03. ~28 seconds
for API to be reachable. Normal for simultaneous reboot.

_____________________________________________________________________

# Theory 1: Vault is slow during boot — REJECTED

Added debug annotation to get verbose logs:

```
[root@k8s-master1 ~]# kubectl patch deploy remediation -n remediation --type='merge' -p '{
  "spec":{"template":{"metadata":{"annotations":{
    "vault.hashicorp.com/log-level":"debug"
  }}}}}'
```

Debug logs showed vault-agent-init completing in 420ms on a healthy cluster:

```
2026-04-26T16:31:16.218Z [INFO]  agent.sink.file: file sink configured: path=/home/vault/.vault-token
2026-04-26T16:31:16.430Z [DEBUG] agent: (runner) final config:
  {"Vault":{"Address":"https://vault.lab.local:8200","Retry":{"Attempts":12,"Backoff":250000000,
  "MaxBackoff":60000000000},"SSL":{"CaCert":"/vault/tls/ca.crt","Verify":true},
  "Transport":{"TLSHandshakeTimeout":10000000000,"MaxConnsPerHost":10}}}
2026-04-26T16:31:16.573Z [DEBUG] agent: (runner) starting
2026-04-26T16:31:16.638Z [DEBUG] agent: (runner) rendering "(dynamic)" => "/vault/secrets/proxmox-creds"
2026-04-26T16:31:16.638Z [INFO]  agent: (runner) rendered "(dynamic)" => "/vault/secrets/proxmox-creds"
```

Auth, secret read, template render — all sub-second (16:31:16.218 → 16:31:16.638 = 420ms).
Config shows 12 retries, 250ms initial backoff, 60s max backoff, TLS verify on.

Ran multiple rollout restarts. Consistently 39-65 seconds. Zero restarts.
This time it started fast. Even faster next try — 39 seconds.
The 5-minute delay ONLY happens during cold boot.

```
NAME                          READY   STATUS            RESTARTS       AGE
remediation-774679955-fbtg6   2/2     Running           12 (58m ago)   41h
remediation-b8959bd7d-fb6x2   0/2     PodInitializing   0              37s
remediation-b8959bd7d-fb6x2   2/2     Running           0              65s
```

65 seconds to 2/2 Running. Zero restarts. Even faster next try:

```
[root@k8s-master1 ~]# kubectl get pods -n remediation
NAME                           READY   STATUS        RESTARTS   AGE
remediation-774bbd48d9-8q8wt   2/2     Running       0          39s
remediation-b8959bd7d-fb6x2    2/2     Terminating   0          3m59s
```

Healthy cluster rollout restart = 39-65 seconds. No 5-minute delay.
First attempt was way after boot and all DNS and other stuff was normal.
Now it runs in 39 seconds. Likely a DNS resolution or TLS handshake
that hung on that specific attempt? No — wrong theory, because the
first attempt was way after boot.

# WordPress baseline — vault works fine on workers

This example of the rollout of WordPress which also depends on vault
injector. WordPress also uses vault-agent-inject for secrets:

```
[root@k8s-master1 ~]# kubectl get pods -n apps -w
wordpress-d56c9dfdb-xbjnb  0/2  Pending         0  0s
wordpress-d56c9dfdb-xbjnb  0/2  Init:0/2        0  0s
wordpress-d56c9dfdb-xbjnb  0/2  Init:1/2        0  1s
wordpress-d56c9dfdb-xbjnb  0/2  PodInitializing 0  2s
wordpress-d56c9dfdb-xbjnb  1/2  Running         0  3s
wordpress-d56c9dfdb-xbjnb  2/2  Running         0  9s
```

9 seconds. vault-agent-init completed in ~1 second. Same Vault server,
same injector. WordPress on workers. Remediation on masters.

# Full reboot reproduction

Will the debug annotation survive a reboot? Yes — pod recreated from
etcd spec which has the annotation. Flux starts later (needs API + DNS
+ Git) → reconciles → removes annotation. But boot window gets captured.

Reproduced with full masters reboot. After stabilization, vault-agent-init
debug logs showed it completed in 47ms:

```
2026-04-26T16:39:47.020Z [INFO]  agent.sink.file: creating file sink
2026-04-26T16:39:47.020Z [INFO]  agent.sink.file: file sink configured: path=/home/vault/.vault-token
2026-04-26T16:39:47.020Z [DEBUG] agent: (runner) starting
2026-04-26T16:39:47.067Z [INFO]  agent: (runner) rendered "(dynamic)" => "/vault/secrets/proxmox-creds"
```

47ms. But describe showed the container was "Started" 5+ minutes ago.
The entire 5-minute gap happened BEFORE vault agent produced its first
log line.

# Kubelet journal: Node Authorization errors

```
[root@k8s-master2 ~]# journalctl -u kubelet | grep -i "remediation"
Apr 26 19:43:31 k8s-master2.lab.local kubelet[1923]: E0426 19:43:31.730054
  "Failed to watch" err="failed to list *v1.Secret: secrets \"vault-ca\" is forbidden: User
  \"system:node:k8s-master2.lab.local\" cannot list resource \"secrets\" in API group \"\" in the namespace
  \"remediation\": no relationship found between node 'k8s-master2.lab.local' and this object"
Apr 26 19:43:31 k8s-master2.lab.local kubelet[1923]: E0426 19:43:31.730256
  "Failed to watch" err="failed to list *v1.ConfigMap: configmaps \"remediation-script\" is forbidden: User
  \"system:node:k8s-master2.lab.local\" cannot list resource \"configmaps\" in API group \"\" in the namespace
  \"remediation\": no relationship found between node 'k8s-master2.lab.local' and this object"
Apr 26 19:43:32 k8s-master2.lab.local kubelet[1923]: E0426 19:43:32.705399
  Couldn't get configMap remediation/remediation-script: failed to sync configmap cache: timed out
```

Node Authorization — kubelet can't access pod's secrets/configmaps until
API server establishes the node-to-pod relationship. The mount thing is
related to just the master startup rush, would complete within 30 seconds
or a minute because other env was ready that time. But why the extra 4 min?

Pod describe confirmed FailedMount:

```
Events:
  Warning  FailedMount     7m     kubelet  MountVolume.SetUp failed for volume "kube-api-access-xzb2p":
    [failed to fetch token: serviceaccounts "remediation" is forbidden: User
    "system:node:k8s-master2.lab.local" cannot create resource "serviceaccounts/token" in API group ""
    in the namespace "remediation": no relationship found between node 'k8s-master2.lab.local' and this object,
    failed to sync configmap cache: timed out waiting for the condition]
  Normal   SandboxChanged  6m27s  kubelet  Pod sandbox changed, it will be killed and re-created.
  Normal   Started         6m27s  kubelet  vault-agent-init: Container started
  Normal   Pulling         42s    kubelet  Pulling image "ghcr.io/mohamedsabry-dev/remediation:latest"
  Normal   Pulled          42s    kubelet  Successfully pulled image in 793ms
  Normal   Started         41s    kubelet  Container started
```

FailedMount at 7m → SandboxChanged at 6m27s = ~33 seconds for Node Auth.
But vault-agent-init Started 6m27s → main container Pulling 42s = still ~5.5 min gap.
Node Auth resolved quick. The 5-min gap is INSIDE vault-agent-init.

But vault injector on master nodes also survived fast:

```
[root@k8s-master2 ~]# kubectl describe pod vault-agent-injector-778c55db9b-9mzwq -n vault | tail
Events:
  Warning  FailedMount     38m                kubelet  MountVolume.SetUp failed for volume
"kube-api-access-xzb2p" : [failed to fetch token: serviceaccounts "vault-agent-injector" is forbidden:
User "system:node:k8s-master2.lab.local" cannot create resource "serviceaccounts/token"...]
  Normal   SandboxChanged  38m (x2 over 38m)  kubelet  Pod sandbox changed...
  Normal   Pulled          38m                kubelet  Container image "hashicorp/vault-k8s:1.7.2" already present
  Normal   Started         38m                kubelet  Container started
```

Same FailedMount → SandboxChanged → Started. Vault-injector recovered fast.
Only pods WITH vault-agent-init have the 5-min delay.

# Theory 2: DNS not ready (CoreDNS on workers) — WRONG TIMING

Thought maybe vault-agent-init was retrying DNS lookups for
vault.lab.local while CoreDNS was still booting. Makes sense in theory:
CoreDNS was on workers (fixed in TS-K8S-053), workers boot 3 min after
masters.

But then I checked: vault-agent-init debug logs start at 16:39:47 and
finish at 16:39:47 (47ms). If it had been retrying DNS for 4 minutes,
there would be error lines before that timestamp. There weren't.

# WordPress vs remediation — simultaneous test

Not so logical because WordPress got the secrets so quick on deployment
restart at same time which remediation and alertmanager was still stuck
and continued another 3 min stuck.

WordPress got Vault secrets under 1 second. Vault responding instantly
to workers at the exact same time remediation stuck on masters.
Killed both "Vault is slow" and "DNS is down" theories in one test.

# Theory 3: Calico network disruption — REJECTED

Thought calico-node cycling through SandboxChanged killing active TCP
connections from vault-agent-init. The capture test done on master1 —
forgot to change it to master2 after the pod moved to 2. tcpdump on
master1 showed DNS queries but no TCP to Vault because TCP goes directly
from master2 to 10.0.52.100, bypassing master1.

tcpdump on master2 — 0 packets during stuck window:

```
[root@k8s-master2 k8s_admin]# tcpdump -i any -n port 8200 -tttt
0 packets captured
204 packets received by filter
```

vault-agent-init not even attempting network connections. Not stuck on
network — never got far enough to try.

# Theory 4: CPU/resource starvation — REJECTED

If I set the CPU of masters to 6 CPU instead of 2, different result?
But the CPU on Proxmox for the 3 masters is 10% all the time, and
almost no IO delay. Why should I trust this theory.

Checked Proxmox: 10% CPU utilization all 3 masters. Resource starvation
doesn't hold when the node isn't actually loaded.

# Exec into stuck container — the clue

Need to check the vault injector config and logic about vault agent init
first run on a node and why the wait for 5 min avg, and how it does it
without having a sleep command inside the container.

Exec'd into vault-agent-init while it was stuck at 4 minutes uptime:

```
/ $ ls vault/secrets/
(empty)
/ $ ls vault/tls/
ca.crt
```

Container alive. Volumes mounted. Network reachable (ping vault.lab.local = 0.4ms).
But /vault/secrets/ empty — secret never written. No error. No sleep. Just sitting there.

# Evidence summary at this point

| Test                                        | Result                                          |
|---------------------------------------------|-------------------------------------------------|
| DNS from inside vault-agent-init            | Works (ping vault.lab.local = 0.4ms)            |
| Vault auth from masters                     | Works (but 3s instead of 36ms)                  |
| Vault secret read for WordPress (workers)   | Works instantly — 13s total rollout              |
| Vault secret read for remediation (masters) | HANGS at "watching 1 dependencies"               |
| Vault secret read for alertmanager (masters) | Same hang                                       |
| vault-agent-init uptime while stuck         | 4 minutes — container alive, /vault/secrets/ EMPTY |
| vault-agent-injector (no init container)    | Recovers in ~80 seconds                         |

Pattern: every pod with vault-agent-init ON MASTERS hangs.
Every pod with vault-agent-init ON WORKERS works fine. At the same time.

# Deeper: crictl + containerd journal

Used crictl to inspect the container at the runtime level:

```
[root@k8s-master2 ~]# crictl inspect <container-id> | jq '.info.config'
{
  "annotations": {
    "io.kubernetes.container.restartCount": "8",
    "io.kubernetes.container.terminationMessagePath": "/dev/termination-log"
  },
  "command": ["/bin/sh", "-ec"],
  "args": ["echo ${VAULT_CONFIG?} | base64 -d > /home/vault/config.json && vault agent -config=/home/vault/config.json"],
  "envs": [
    {"key": "NAMESPACE", "value": "remediation"},
    {"key": "VAULT_CONFIG", "value": "<base64-encoded-config>"}
  ]
}
```

Entrypoint: `/bin/sh -ec "echo ${VAULT_CONFIG} | base64 -d > config.json && vault agent -config=config.json"`
Shell has to: 1) decode VAULT_CONFIG 2) write config.json 3) exec vault binary.
If vault binary can't load from disk, shell blocks on step 3.

containerd journal: StartContainer returned at 00:27:43 — runtime said
"container started" immediately. Process inside didn't produce output until
00:32:xx. createdAt vs startedAt delta 2 seconds — runtime startup normal.
Delay between process exec and first output.

# The breakthrough: disk IO starvation

While operating worker2 and testing, the database 6 min delay on vault
init, the VM hung for moment 5 or 15 seconds which made me run top and
didn't find abnormality. Which made me go look at Proxmox CPU and mem
and IO of this VM and noted the graph of the IO maxed to 30 and capped.

# Root cause: Proxmox disk IO graph

Graph showed reads hitting exactly 31.26 MB/s at 00:29:00 — matched
precisely against configured read limit of 30 MB/s on the VM's scsi0
disk. Hitting the throttle ceiling and being hard-limited.

Checked Proxmox disk bandwidth config (Hardware → Hard Disk → Edit → Bandwidth):

```
Read limit:   30 MB/s      Read max burst:   80 MB
Write limit:  20 MB/s      Write max burst:  40 MB
Read IOPS:   500           Read max burst:  1500
Write IOPS:  300           Write max burst:  800
```

Values appropriate for an archive NAS disk, not a k8s compute node.
Applied as part of TS-PVE-017 (Proxmox disk config).

This explained everything:

1. vault-agent-init starts → shell runs `vault agent -config=...`
2. Go runtime needs to page the vault binary from overlayfs into memory
3. Vault image is ~250MB with multiple overlay layers
4. At 30 MB/s read cap with 500 IOPS, loading those pages takes minutes
5. The shell blocks on the execve — vault binary can't be paged in
6. No logs, no network, nothing — vault agent never started executing
7. Once pages are in cache, subsequent restarts are instant (cache hit)

This is why:
- Cold boot = slow (pages not in cache, all 6 VMs thrashing disk)
- Rollout restart = fast (pages already cached from previous run)
- Workers = fast (fewer competing processes, less disk contention)
- Masters = slow (etcd + apiserver + calico all doing heavy IO at boot)

_____________________________________________________________________

[Final Root Cause]
Proxmox disk bandwidth throttle on the VM's scsi0 disk was set to
30 MB/s read and 500 IOPS. During cold boot, containerd needs to read
vault image overlay layers (~250MB) from disk into the page cache. At
30 MB/s hard cap, the kernel page-faults every segment of the vault
binary one throttled chunk at a time, turning a 2-3 second burst read
into a 5+ minute crawl.

Process alive (PID existed) but shell blocked on the execve — waiting
for vault binary to be paged in by the OS. No logs, no network, nothing
visible because vault agent never actually started executing during that
entire window.

Only manifests on first scheduling on fresh VM because subsequent
restarts find vault binary layers already in page cache from previous
run, bypassing disk. Why it looks like first-boot-only issue and why
rollout restarts are fast.

30 MB/s config from TS-PVE-017. Appropriate for archive storage, not
for k8s compute nodes running 250MB Go binaries from overlayfs.

_____________________________________________________________________

[Final Solution]

Set disk IO limits to 125 MB/s read/write with 150 MB/s max burst for
all k8s VMs. Applied via Terraform across the whole cluster:

→ terraform/dev/proxmox/vms/k8s_masters/main.tf (and workers, and prod)

80 MB/s enough for workers but went 125/150 across all nodes for
consistency. Masters need headroom — 6 VMs boot simultaneously doing
heavy overlay reads at the same time.

# Verification

Before fix:
```
Normal  Started  5m ago  kubelet  spec.initContainers{vault-agent-init}: Container started
# ... 5 minutes of silence ...
Normal  Started  5m ago  kubelet  spec.containers{remediation}: Container started
```

After fix:
```
Normal  Started  12s ago  kubelet  vault-agent-init: Container started
Normal  Started   5s ago  kubelet  spec.containers{remediation}: Container started
Normal  Started   4s ago  kubelet  spec.containers{vault-agent}: Container started
```

vault-agent-init: **5 minutes 18 seconds → ~7 seconds**.

Disk IO graph after fix — reads freely bursting to 60-70 MB/s in a
natural spike-then-settle pattern. Expected behavior when overlay layers
loaded into page cache on first access.

_____________________________________________________________________

[Evidence Table]

| Check | Result | Conclusion |
|---|---|---|
| Pod events timeline | 5-min gap init→main | Confirmed delay |
| vault-agent-init debug logs | 420ms total | Agent code is fast |
| Rollout restart (healthy) | 39-65s, zero restarts | Not a code bug |
| WordPress (workers, same time) | 13s with vault secrets | Vault server fine |
| Node Auth (FailedMount) | Resolves in ~33s | Not the bottleneck |
| Vault audit log | Request arrives AFTER 5-min delay | Vault never received it |
| tcpdump master2 port 8200 | 0 packets during stuck window | No TCP to Vault |
| Exec into stuck container | /vault/secrets/ empty, no sleep | Container alive but idle |
| crictl inspect | createdAt→startedAt = 2s | Runtime startup normal |
| containerd journal | StartContainer returned immediately | Runtime innocent |
| Proxmox disk IO graph | Flat at 31.26 MB/s = throttle | **Root cause** |
| Disk bandwidth config | Read 30MB/s / 500 IOPS | Throttle confirmed |
| After throttle fix | 5m18s → ~7s | Fix verified |

_____________________________________________________________________

[Risk Level] MEDIUM

Boot-time only issue. Self-resolves once overlay pages are cached. No
data loss, no service disruption beyond the boot window. But it stacks
with other boot-time delays (CoreDNS, Calico BGP) making the overall
boot-to-stable time unnecessarily long.

_____________________________________________________________________

[Decision Notes]

Spent long time chasing this because symptoms pointed everywhere except
disk IO. No errors, no logs, no network activity — looked like the
process wasn't running at all. Every theory I tested (DNS, Vault, Calico,
CPU) either completely wrong or didn't explain the 5-minute delay.

Breakthrough was the VM hung for a moment during testing — went to check
Proxmox IO graph and saw reads capped at exactly the configured throttle
limit. That moved the whole investigation from "what's wrong with
vault-agent" to "what's wrong with this VM's IO."

Lesson: when a container is "started" but producing nothing — not even
error logs — check the disk before chasing application-layer theories.
Throttled disk can make a binary page-fault for minutes without any
visible error.

Case noticed 25 April, drafted for check on 26 April. Debugged across
26 April and into 27 April 2:00 AM. Issue solved al hamdllah.

_____________________________________________________________________

[References]
- TS-K8S-053 — CoreDNS boot delay (found during same investigation)
- TS-K8S-033 — Vault Agent DNS failure (similar symptoms, different cause)
- TS-PVE-017 — Proxmox disk throttle config (source of the 30 MB/s limit)
- terraform/dev/proxmox/vms/k8s_masters/main.tf — updated disk speed config
- terraform/dev/proxmox/vms/k8s_workers/main.tf — same
- terraform/prod/proxmox/vms/k8s_masters/main.tf — same
- terraform/prod/proxmox/vms/k8s_workers/main.tf — same
