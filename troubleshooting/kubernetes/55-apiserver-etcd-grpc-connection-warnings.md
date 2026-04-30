# TS-K8S-055 | 2026-04-30 | WORKAROUND APPLIED
_____________________________________________________________________

[Info]
Domain: Kubernetes / API Server / etcd / gRPC
Sub-techs: kube-apiserver, etcd 3.6.6, gRPC transport, static pods,
           kubeadm, Loki log analysis, tcpdump
Environment: DEV + PROD k8s clusters | 3 masters (kubeadm) + 3 workers each
Severity: UNKNOWN
Reason re-opened: Not about impact — it's about log hygiene. These
                  errors make log reading a nightmare. During TS-K8S-056
                  I was trying to monitor the cluster via Loki to confirm
                  things were OK during rolling restarts, and this error
                  stream kept dirtying the place. Can't rely on Loki for
                  real-time monitoring if every query is buried under
                  gRPC noise that means nothing.
Discovered during: DR Test — Control Plane Component Failures (scenario 1a),
                   while checking apiserver logs via Loki
Related: TS-K8S-039 (kube-system TargetDown — etcd scraping portion still open)
Re-opened: Yes — 2026-04-30, same session. Log noise made Loki
            unusable for real monitoring during TS-K8S-056 rollout

_____________________________________________________________________

[Issue Description]
All kube-apiserver pods across all masters on both dev and prod clusters
are logging gRPC connection warnings to `127.0.0.1:2379` (local etcd)
every ~30 seconds. Constant stream, non-stop, since boot stabilization.

The error is always the same:
```
W0430 logging.go:55] [core] [Channel #NNNN SubChannel #NNNN]
grpc: addrConn.createTransport failed to connect to
{Addr: "127.0.0.1:2379", ServerName: "127.0.0.1:2379"}
Err: connection error: desc = "transport: Error while dialing:
dial tcp 127.0.0.1:2379: operation was canceled"
```

Despite these warnings, all etcd pods are healthy and the cluster
operates normally. No visible impact on API operations.

_____________________________________________________________________

[Analysis]

# How I found it

Was running DR test scenario 1a (scheduler down on 1 node). After
observing the scheduler leader election via Loki, I went to check the
apiserver logs to see how the API interacted with the remaining
schedulers.

Instead of scheduler-related logs, I found a wall of gRPC errors —
the apiserver constantly failing to connect to local etcd at
127.0.0.1:2379.

LogQL query used:
```
{namespace="kube-system", pod=~"kube-apiserver-k8s-master1.*"} |= "2379" |= "error"
```

# Scope check — is this just master1?

Checked all masters on dev:
- master1: same errors, every ~30 seconds
- master2: same errors, every ~30 seconds
- master3: same errors, every ~30 seconds

Checked all masters on prod (untouched, no DR test running):
- Same errors on all 3 prod masters

This is not related to the DR test or the bind-address fix (TS-K8S-054).
It's present on every apiserver in both clusters. Likely from day 1.

# Timeline analysis (dev, today)

Boot at 11:28. Environment stabilized by ~11:40. Errors appear
continuously from 11:41 onward through at least 13:27 (when I stopped
checking). Not boot noise — steady state.

Channel numbers climbing over time:
- 11:41 → Channel #580
- 13:23 → Channel #2488

Apiserver keeps creating new gRPC subchannels that fail and get
replaced. ~30 second interval between errors.

# etcd config and listen addresses

```
[root@k8s-master1 ~]# cat /etc/kubernetes/manifests/etcd.yaml | grep listen-client
    - --listen-client-urls=https://127.0.0.1:2379,https://10.0.61.10:2379
```

```
[root@k8s-master1 ~]# ss -tlnp | grep 2379
LISTEN 0  4096  10.0.61.10:2379  0.0.0.0:*  users:(("etcd",pid=2245,fd=6))
LISTEN 0  4096   127.0.0.1:2379  0.0.0.0:*  users:(("etcd",pid=2245,fd=9))
```

etcd listening on both `127.0.0.1:2379` and `10.0.61.10:2379`. IPv4
only, no IPv6. TLS required (`--client-cert-auth=true`).

# apiserver etcd config

```
[root@k8s-master1 ~]# cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep etcd
    - --etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt
    - --etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client.crt
    - --etcd-keyfile=/etc/kubernetes/pki/apiserver-etcd-client.key
    - --etcd-servers=https://127.0.0.1:2379
```

Single endpoint, localhost, TLS with client certs. Standard kubeadm
config.

# etcd health check

```
[root@k8s-master1 ~]# etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/apiserver-etcd-client.crt \
  --key=/etc/kubernetes/pki/apiserver-etcd-client.key endpoint health
https://127.0.0.1:2379 is healthy: successfully committed proposal: took = 6.431497ms
```

etcd responds in 6ms. Healthy.

etcdctl version: 3.6.6, API version: 3.6

# Active connections

```
[root@k8s-master1 ~]# ss -tnp | grep 2379 | head -20
ESTAB  127.0.0.1:2379   127.0.0.1:52224  users:(("etcd"...))
ESTAB  127.0.0.1:2379   127.0.0.1:52736  users:(("etcd"...))
ESTAB  127.0.0.1:44852  127.0.0.1:2379   users:(("kube-apiserver"...))
ESTAB  127.0.0.1:47384  127.0.0.1:2379   users:(("kube-apiserver"...))
ESTAB  127.0.0.1:43550  127.0.0.1:2379   users:(("kube-apiserver"...))
... (20+ established connections)
```

Dozens of healthy ESTAB connections between apiserver and etcd. All
working. The gRPC warnings are happening alongside fully functional
connections.

# tcpdump — no failed TCP connections

```
[root@k8s-master1 ~]# timeout 60 tcpdump -i lo port 2379 -nn -c 50
```

All captured packets are normal data exchange on established
connections. No SYN failures, no RST packets, no connection teardowns.

Filtered for connection setup/teardown specifically:
```
[root@k8s-master1 ~]# timeout 35 tcpdump -i lo port 2379 -nn 2>&1 | grep -E "SYN|RST|FIN"
```

Nothing. No TCP connection attempts are being made or rejected.
The gRPC "operation was canceled" happens before any TCP socket is
opened — entirely internal to the gRPC library.

# Loki — no real etcd errors

```
{namespace="kube-system", pod=~"kube-apiserver-k8s-master1.*"} |= "etcd"
```

No results. The apiserver logs contain zero mentions of "etcd" at all.
The only etcd-related entries are the gRPC transport warnings which
reference `127.0.0.1:2379` but not the word "etcd."

# What this is NOT

- NOT Prometheus/Alertmanager trying to scrape etcd — that would be
  HTTP on port 2381 (metrics), not gRPC on 2379
- NOT related to the DR test — present on all masters including prod
- NOT related to the bind-address fix (TS-K8S-054) — was happening
  before and after the fix
- NOT causing any visible cluster impact — everything works normally
- NOT an IPv6 mismatch (Talos #12542) — etcd is IPv4 only
- NOT a network-level failure — tcpdump shows no failed TCP connections

# Upstream reference — Talos issue #12542

Found a similar report: https://github.com/siderolabs/talos/issues/12542

Their issue: etcd was listening on IPv6 `[::1]:2379` only, not IPv4
`127.0.0.1:2379`. Fixed in Talos PR #12566.

Our case is different — etcd confirmed listening on IPv4 `127.0.0.1`.
Same error message but different underlying cause.

# What I know so far

| Check | Result |
|---|---|
| etcd pods | All 3 healthy, Running |
| etcd health (etcdctl) | Healthy, 6ms response |
| Active connections (ss) | 20+ ESTAB between apiserver and etcd |
| tcpdump SYN/RST/FIN | None — no failed TCP connections |
| tcpdump full capture | All normal data exchange |
| Loki real etcd errors | None |
| Scope | All masters, both dev and prod clusters |
| Pattern | Every ~30 seconds, channel numbers climbing |
| Where it happens | Inside gRPC library, before TCP socket opens |
| Cluster impact | None observed |

# Re-opened investigation — keepalive and health check analysis

Reason for re-opening: during TS-K8S-056 rolling restarts I was
monitoring the cluster via Loki to confirm things were OK. The gRPC
error stream made it a nightmare — every query buried under noise
that means nothing. Can't rely on Loki for real-time monitoring if
the logs are this dirty.

Checked etcd keepalive config:
```
cat /etc/kubernetes/manifests/etcd.yaml | grep -i keep
(nothing — no keepalive configured, using gRPC defaults: 2h keepalive time)
```

Checked apiserver transport config:
```
cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep -i -E "etcd|keep|transport|dial"
    - --etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt
    - --etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client.crt
    - --etcd-keyfile=/etc/kubernetes/pki/apiserver-etcd-client.key
    - --etcd-servers=https://127.0.0.1:2379
(no keepalive, no transport tuning — bare minimum config)
```

Checked etcd logs for GOAWAY / keepalive rejections:
```
crictl logs $(crictl ps --name etcd -q | head -1) 2>&1 | grep -i -E "goaway|reject|keepalive|too_many"
(nothing — only normal Raft vote rejections, no gRPC-level rejections)
```

Cluster health check:
```
etcdctl endpoint health --cluster
https://10.0.61.10:2379 is healthy: took = 5.75ms
https://10.0.61.11:2379 is healthy: took = 7.58ms
https://10.0.61.12:2379 is healthy: took = 8.01ms
```

# What's ruled out after this round

- NOT a keepalive mismatch — etcd has no keepalive config, using
  defaults (2h), and etcd logs show zero GOAWAY or keepalive rejections
- NOT etcd rejecting connections — no rejection logs at all
- NOT apiserver misconfigured — config is correct, points at 127.0.0.1:2379
- NOT etcd listening on wrong address — confirmed working on 127.0.0.1

# What's left

The gRPC client library inside the apiserver is doing this to itself.
Every ~30 seconds it creates a new subchannel, starts to dial, then
cancels its own dial before the TCP handshake even starts. The 20+
existing connections keep working fine.

Points to either:
1. gRPC client-side health checking — something about the TLS
   negotiation timing causes it to cancel and retry
2. Known bug in etcd 3.6.x or k8s 1.35's gRPC client version —
   a regression in connection pool management

Next: search upstream for known issues with this specific pattern.

# Upstream root cause — etcd client v3.6.x resolver bug

Found the exact bug: etcd-io/etcd#21660

`EtcdManualResolver.Build()` sends two resolver updates to gRPC in
rapid succession with different ServiceConfig values. gRPC sees the
config change, switches load balancers mid-connection, tears down
in-flight subchannels — new subchannel created, old dial canceled,
the warning we see. Repeats every ~30 seconds as the resolver
re-triggers.

Confirmed to produce exactly our error:
```
grpc: addrConn.createTransport failed to connect to
{Addr: "127.0.0.1:2379"} Err: connection error: desc =
"transport: Error while dialing: dial tcp 127.0.0.1:2379:
operation was canceled"
```

Fix: PR etcd-io/etcd#21662 — moves `updateState()` before `Build()`
so gRPC gets one atomic update instead of two. Not merged yet, still
under review.

Affected: all etcd client v3.6.x (our etcd 3.6.6 included).

Also found: grpc/grpc-go#8654 tried to suppress these warnings at
the gRPC level, but grpc-go maintainers rejected it — they consider
failed connection attempts important diagnostic events even when the
root cause is expected. hashicorp/consul#17842 hit the exact same
gRPC library behavior and also couldn't suppress it.

# Timeline — when did this start?

Loki query: `{namespace="kube-system", pod=~"kube-apiserver.*"} |= "addrConn.createTransport"`

Full retention range shows:
- April 2 to April 15: ZERO occurrences
- First occurrence: April 16, ~19:00 (7 PM)
- From that point: constant, every ~30 seconds, never stops

April 16 7 PM is when I start the server after coming home from work.
So whatever operation caused this happened on April 14 or 15 — the
server was off between then and the 16th. The error started on first
boot after that operation.

Checking what happened around April 14-15 to identify the trigger.

Operations around April 14-16 (from troubleshooting/DR records):

- **April 14:** TS-K8S-030 — worker3 VM crashed from memory exhaustion.
  During the fix, Terraform applied memory changes to all 3 workers
  simultaneously. Parallel reboots → ~30 seconds complete cluster
  downtime. All worker VMs restarted.

- **April 15:** IPA Domain Down DR Test Part 1 — discovered vault
  agent DNS failures, Ansible SSH slowness, WordPress external DNS
  failures. Multiple pod crashes and restarts.

- **April 15-16:** IPA Domain Down DR Test Part 2 — CoreDNS config
  changes (added hosts plugin for vault.lab.local), pod restarts
  during outage, 4 major fixes applied (TS-K8S-033, TS-K8S-034,
  TS-LNX-003, TS-IDN-009).

- **April 16:** External NGINX and Ingress NGINX DR tests — more
  pod kills and restarts.

The first gRPC warning appeared April 16 ~19:00 — that's server
start after I came home from work. The operations that triggered
this happened April 14-15 while the cluster was being heavily
restarted and reconfigured. When the apiserver reconnected to etcd
with fresh gRPC channels after those operations, the resolver bug
in etcd client v3.6.x kicked in and never stopped.

Checked bash history on master1 — no `kubeadm upgrade` or `dnf upgrade`
commands found. k8s and etcd versions haven't changed since initial
setup. Only etcdctl CLI was installed manually (v3.6.6) — that's the
client tool, not the server.

Loki was deployed April 8 — a full week before the first warning on
April 16. So Loki was running and would have captured earlier
occurrences. The warnings genuinely started around April 16, not
from day 1.

Further investigation: queried Loki for the earliest apiserver log
of any kind — oldest entry is April 16 20:40. Checked etcd logs —
oldest is April 16 20:07. Thought Loki wasn't scraping before that.

Then checked the PVCs — Loki PVC is only 6 days old (created ~April 24).
I deleted and recreated the Loki PVC around that time to change some
config. All log history before the PVC recreation is gone. Both dev
and prod Loki PVCs show the same 6d age — both lost their history.

With 7-day retention + 6-day-old PVC, the April 16 "start date" is
just the oldest data Loki still has. Not when the bug started.

Conclusion: the gRPC warnings have been there since day 1 with
etcd 3.6.6. The upstream resolver bug (etcd-io/etcd#21660) exists
in all v3.6.x releases. No local trigger — it's a code bug in the
etcd client library that fires on every apiserver-to-etcd connection.

_____________________________________________________________________

[Final Root Cause]
etcd client v3.6.x bug — `EtcdManualResolver.Build()` sends two
resolver updates to gRPC in rapid succession (etcd-io/etcd#21660).
First update has endpoints only, second adds round_robin ServiceConfig.
gRPC sees the config change, switches load balancers mid-connection,
tears down in-flight subchannels, new subchannel gets created then
immediately canceled. Produces the warning every ~30 seconds.

Not a config issue. Not a keepalive mismatch. Not etcd rejecting
connections. The gRPC client is doing this to itself because of a
race in the resolver initialization.

_____________________________________________________________________

[Final Solution]
WAITING ON UPSTREAM — PR etcd-io/etcd#21662 fixes the double
resolver update by moving `updateState()` before `Build()` so gRPC
gets one atomic update. Not merged yet, still under review.

No local fix available:
- grpc-go maintainers rejected suppressing the warning (grpc/grpc-go#8654)
- No apiserver flag to control gRPC log verbosity for this
- hashicorp/consul#17842 hit the same gRPC behavior, also no fix

Workaround applied: Promtail drop filter to suppress the noise at
ingestion level (see below).

# The second variant — authentication handshake

After the Promtail filter removed the "operation was canceled" storm,
a second error variant became visible that was buried under the noise:

```
grpc: addrConn.createTransport failed to connect to
{Addr: "127.0.0.1:2379"} Err: connection error: desc =
"transport: authentication handshake failed: context canceled"
```

Less frequent (~every 7 minutes vs every 30 seconds), but same
`addrConn.createTransport`, same `canceled`. I suspected this might
actually be the cause of the main error — a TLS handshake getting
canceled could trigger the resolver to cycle subchannels. But I
don't have evidence to confirm that connection.

Searched online — found kubernetes/kubernetes#125770 with comments
showing the exact same "authentication handshake failed: context
canceled" pattern across k8s 1.28+. Looks related to the same
resolver bug but can't confirm if it's cause or effect.

Decided to filter both variants — broadened the Promtail drop to
catch any `addrConn.createTransport.*canceled` pattern. It's the
practical solution until upstream fixes it.

# Promtail filter applied

Added drop pipeline stage to Promtail config (both dev and prod):
```yaml
config:
  snippets:
    pipelineStages:
      - cri: {}
      - drop:
          expression: ".*addrConn\\.createTransport.*canceled.*"
```

Files changed:
- kubernetes/dev/deployments/apps/logging/logging.yaml
- kubernetes/prod/deployments/apps/logging/logging.yaml

Flux deploys the change → Promtail restarts → noise stops appearing
in Loki. The apiserver still generates the warnings (can't stop that
until upstream fix), but they never reach Loki storage.

_____________________________________________________________________

[Risk Level] LOW

No cluster impact observed. All etcd operations work normally. All
connections are healthy at TCP level. The warnings are at gRPC W
(warning) level, not error. But the pattern — every 30 seconds on
every master on both clusters — is unexplained.

_____________________________________________________________________

[References]
- Discovered during DR Test — GROUP 1: Control Plane Component Failures, scenario 1a
- TS-K8S-039 — kube-system TargetDown false positives (etcd portion still open)
- TS-K8S-054 — Scheduler + controller-manager bind-address fix (same DR session)
- https://github.com/siderolabs/talos/issues/12542 — similar error, different root cause (IPv6)
- https://medium.com/zeal-tech-blog/kubernetes-debug-story-side-effect-of-a-privileged-container-446d56a7a422 — similar error caused by iptables MASQUERADE, not our case
- LogQL: `{namespace="kube-system", pod=~"kube-apiserver.*"} |= "2379" |= "error"`
- etcd-io/etcd#21660 — root cause: double resolver update in EtcdManualResolver.Build()
- etcd-io/etcd#21662 — fix PR (not merged yet)
- grpc/grpc-go#8654 — attempt to suppress warning, rejected by maintainers
- hashicorp/consul#17842 — same gRPC behavior in Consul, confirmed no impact
- kubernetes/kubernetes#125770 — same error reported across k8s versions (1.28+), comments confirm both "operation was canceled" and "authentication handshake failed: context canceled" variants
- TS-K8S-056 — cgroup fix session where log noise made Loki monitoring a nightmare
- Versions: k8s v1.35.3, etcd 3.6.6, kubeadm cluster
