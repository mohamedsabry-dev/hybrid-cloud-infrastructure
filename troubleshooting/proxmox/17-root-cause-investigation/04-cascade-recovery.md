# TS-PVE-017 Cascade Recovery — Break-Glass Procedure

**Status**: TESTED AND VALIDATED (2026-04-24 during live incident)
**Applies to**: DEV Proxmox host (pve-dev) running K8s HA cluster on constrained hardware

_____________________________________________________________________

## When to Use This

Use this procedure when:
- PSI (Pressure Stall Information) stays elevated >30% for >10 minutes
- Multiple control plane components are in CrashLoopBackOff
- Pod restart counts are growing continuously
- The cluster is in a self-reinforcing cascade loop

Signs of active cascade:
- kube-scheduler CrashLoopBackOff on 2+ masters
- kube-controller-manager CrashLoopBackOff on 2+ masters
- csi-nfs-controller restart count climbing (was 88 during incident)
- Flux controllers CrashLoopBackOff (25-39 restarts)
- kube-state-metrics CrashLoopBackOff
- IO delay on Proxmox host sustained >30%

_____________________________________________________________________

## Critical DO NOTs

**DO NOT reboot VMs** — creates a boot storm that adds MORE IO load. During the incident, rebooting all VMs while in degraded state produced 49-67% sustained PSI for 40+ minutes. The same reboot on a healthy cluster produced only 30% for 3 minutes.

**DO NOT drain nodes** — eviction generates API calls (LIST, DELETE, CREATE on new node) that feed the cascade.

**DO NOT try to fix individual pods** — the problem is systemic. Restarting one pod just adds to the restart storm.

**DO NOT add capacity** — starting new VMs or workers during cascade adds boot-time IO load to an already saturated NVMe.

_____________________________________________________________________

## Step-by-Step Scale-Down

### Step 1: Scale down application workloads

```bash
kubectl -n apps scale deployment --all --replicas=0
kubectl -n database scale statefulset mariadb --replicas=0
```

### Step 2: Suspend Flux (CRITICAL — prevents reconciliation revert)

Flux will fight you by scaling workloads back up to match git state. Shut it down first or it undoes your work.

```bash
kubectl -n flux-system scale deployment --all --replicas=0
```

If Flux controllers are already in CrashLoopBackOff, they may not be actively reconciling, but shut them down anyway to prevent recovery during your procedure.

### Step 3: Scale down monitoring stack

Monitoring is a heavy IO consumer during churn — Prometheus scraping failing endpoints, Promtail shipping error logs, Loki ingesting at high rate.

```bash
kubectl -n monitoring scale deployment --all --replicas=0
kubectl -n monitoring scale statefulset --all --replicas=0
```

### Step 4: Stop daemonsets (nodeSelector trick)

Daemonsets cannot be scaled with `--replicas=0`. Use a nodeSelector that matches no nodes — pods terminate because they can't schedule anywhere.

```bash
kubectl -n monitoring patch daemonset promtail \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"disabled":"true"}}}}}'

kubectl -n monitoring patch daemonset kube-prometheus-stack-prometheus-node-exporter \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"disabled":"true"}}}}}'
```

### Step 5: Stop remediation controller

The remediation controller may auto-bring back nodes or workloads you're trying to exclude.

```bash
kubectl -n remediation scale deployment --all --replicas=0
```

### Step 6: Wait for silence

Wait 15-20 minutes for IO pressure to drop to baseline.

Monitor from the Proxmox host:
```bash
# Watch IO pressure in real-time
watch -n 5 'cat /proc/pressure/io'

# Or check PSI graph in Proxmox GUI → Node → Summary → IO Pressure Stall
```

Target: PSI drops below 5% and stays there.

_____________________________________________________________________

## What Remains Running (Minimum Viable Cluster)

After full scale-down, these components remain (static pods + core infrastructure):

| Component | Count | Notes |
|-----------|-------|-------|
| etcd | 3 | Static pod, cannot be scaled |
| kube-apiserver | 3 | Static pod |
| kube-scheduler | 3 | Static pod |
| kube-controller-manager | 3 | Static pod |
| kube-proxy | 5-6 | DaemonSet, leave running |
| calico-node | 5-6 | DaemonSet, leave running |
| coredns | 2 | Leave running |
| csi-nfs-controller | 2 | Should stabilize on its own |
| csi-nfs-node | 5-6 | DaemonSet, leave running |
| metrics-server | 2 | Light, leave running |
| vault-agent-injector | 2 | Light, leave running |
| ingress-nginx-controller | 2 | Leave running |

_____________________________________________________________________

## Sequential Reintroduction

Once baseline is confirmed stable (PSI < 5% for 15+ minutes), bring services back ONE AT A TIME with 5-minute waits between each step.

I validated this exact order during the 2026-04-24 incident. Every component started with 0 restarts and stabilized immediately.

### Step 1: Prometheus (core monitoring — need visibility first)

```bash
kubectl -n monitoring scale statefulset prometheus-kube-prometheus-stack-prometheus --replicas=1
```
Result during incident: `2/2 Running 0 27s` on worker3. Zero restarts.

Wait 5 minutes. Check PSI.

### Step 2: Grafana (light, gives us dashboards)

```bash
kubectl -n monitoring scale deployment kube-prometheus-stack-grafana --replicas=1
```
Result during incident: `4/4 Running 0 3m49s` on worker1. Zero restarts.

Wait 5 minutes.

### Step 3: Loki (log storage)

```bash
kubectl -n monitoring scale statefulset loki --replicas=1
```
Result during incident: started `1/2`, then `2/2 Running`. Zero restarts.

Wait 5 minutes.

### Step 4: Node-exporter (revert daemonset nodeSelector)

```bash
kubectl -n monitoring patch daemonset kube-prometheus-stack-prometheus-node-exporter \
  -p '{"spec":{"template":{"spec":{"nodeSelector":null}}}}'
```
Result during incident: 6 pods ready in 5 seconds. Zero restarts on all 6.

Wait 5 minutes.

### Step 5: Promtail (the big test — main log shipper)

This was the component I expected to tip things over. Previously had 14+ restarts each during cascade.

```bash
kubectl -n monitoring patch daemonset promtail \
  -p '{"spec":{"template":{"spec":{"nodeSelector":null}}}}'
```
Result during incident: all 6 pods ready in 14 seconds. Zero restarts. "They was never that fast" — because the cluster was healthy this time.

Wait 5 minutes.

### Step 6: kube-state-metrics (apiserver watcher)

```bash
kubectl -n monitoring scale deployment kube-prometheus-stack-kube-state-metrics --replicas=1
```
Result during incident: `1/1 Running 0 13s`. Previously had 13+ restarts in CrashLoopBackOff. Now clean.

Wait 5 minutes.

### Step 7: prometheus-operator

```bash
kubectl -n monitoring scale deployment kube-prometheus-stack-operator --replicas=1
```
Result during incident: `1/1 Running 0 60s`. Zero restarts.

Wait 5 minutes.

### Step 8: Alertmanager

```bash
kubectl -n monitoring scale statefulset alertmanager-kube-prometheus-stack-alertmanager --replicas=1
```

Wait 5 minutes.

### Step 9: MariaDB (database)

```bash
kubectl -n database scale statefulset mariadb --replicas=1
```

Wait 5 minutes.

### Step 10: WordPress (applications)

```bash
kubectl -n apps scale deployment wordpress --replicas=1
```

Wait 5 minutes.

### Step 11: Flux controllers (LAST — will reconcile everything to git state)

Before starting Flux, decide:
- **Option A**: Suspend kustomizations first, then start Flux, then unsuspend one at a time
- **Option B**: Commit reduced replica counts to git, then start Flux
- **Option C**: Just start Flux and let it reconcile (may scale things back up)

```bash
# Start Flux controllers
kubectl -n flux-system scale deployment source-controller --replicas=1
kubectl -n flux-system scale deployment notification-controller --replicas=1
kubectl -n flux-system scale deployment helm-controller --replicas=1
kubectl -n flux-system scale deployment kustomize-controller --replicas=1
```

Result during incident: all 4 controllers started clean, 0 restarts. Flux reconciled wordpress to 2 replicas per git state. Remediation came back online via its own logic.

To suspend kustomizations before starting Flux:
```bash
kubectl get kustomization -A -o name | \
  xargs -I {} kubectl patch {} -n flux-system --type=merge \
  -p '{"spec":{"suspend":true}}'
```

_____________________________________________________________________

## Post-Recovery Verification

```bash
# All pods should be Running or Completed
kubectl get pods -A | grep -v Running | grep -v Completed

# All nodes Ready
kubectl get nodes

# Resource usage should be low
kubectl top nodes

# PSI should be at baseline
cat /proc/pressure/io
```

Expected healthy state (from actual recovery):
```
NAME                    CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
k8s-master1.lab.local   136m         3%       1790Mi          58%
k8s-master2.lab.local   177m         4%       2134Mi          70%
k8s-master3.lab.local   138m         3%       1729Mi          56%
k8s-worker1.lab.local   91m          4%       1631Mi          69%
k8s-worker2.lab.local   87m          4%       1815Mi          77%
k8s-worker3.lab.local   73m          3%       1659Mi          70%
```

_____________________________________________________________________

## Evidence This Procedure Works

### Before scale-down
- Sustained 40-67% PSI for 40+ minutes
- kube-scheduler CrashLoopBackOff on 2 of 3 masters
- kube-controller-manager CrashLoopBackOff on 2 of 3 masters
- csi-nfs-controller: 88 restarts
- Flux controllers: 25-39 restarts

### After scale-down
- IO pressure dropped to baseline within ~5 minutes
- Control plane components stopped crashing
- Restart counts stopped growing

### After sequential reintroduction
- All pods Running with 0 new restarts
- PSI stable at baseline throughout
- 3-4% CPU across all nodes
- 56-77% memory across all nodes
- Promtail (previously 14+ restarts) started in 14 seconds

### What this proved
1. The cluster CAN run all workloads stably on current hardware
2. The cluster CANNOT recover from cascade on its own
3. The issue was cascade dynamics, not hardware exhaustion
4. Sequential startup with 5-min waits prevents cascade re-ignition

_____________________________________________________________________

## Gotchas Discovered During Recovery

### etcd v3.6 env variable conflicts
etcd v3.6+ is strict about environment variable and flag conflicts. If `ETCDCTL_ENDPOINTS` is set in environment AND `--endpoints` is used as a flag, the command fails with a fatal error. `ETCDCTL_API=3` is now unrecognized in v3.6 (emits warning but harmless — v3 is the only API).

Fix: either unset env vars or use them exclusively without flags.

### Cannot scale daemonsets directly
`kubectl scale daemonset --replicas=0` does not work. Use the nodeSelector trick to make pods unschedulable:
```bash
# Disable
kubectl patch daemonset <name> -n <ns> \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"disabled":"true"}}}}}'

# Re-enable
kubectl patch daemonset <name> -n <ns> \
  -p '{"spec":{"template":{"spec":{"nodeSelector":null}}}}'
```

### Flux reconciliation fights manual scaling
If Flux controllers are running, they will revert manual scaling changes to match git state. Scale down Flux BEFORE other workloads, or suspend kustomizations.

### Remediation controller auto-recovery
The remediation controller may automatically bring back nodes or workloads you excluded. During the incident, it brought worker3 back up without being asked. Good for recovery in general, but means "turn it off" isn't always simple.

### Worker memory inconsistency after auto-recovery
Worker3 came back via remediation at its original 2.75GB instead of the 3GB applied to workers 1 and 2 earlier. Memory changes applied while a VM is excluded don't carry over when it's auto-recovered.

### kubectl exec probes depend on NSS/sssd
Container probes that use `kubectl exec` depend on NSS resolution inside the container. If sssd is down, NSS lookups can hang, causing probe timeouts that look like application failures.

_____________________________________________________________________

## Why Sequential Matters

On constrained hardware (single NVMe, limited RAM), parallel startup creates exactly the IO storm that caused the cascade in the first place:
- Each starting component does full LIST operations against apiserver/etcd
- etcd fsyncs WAL entries to the shared NVMe
- Multiple simultaneous startups = multiple concurrent fsync streams
- NVMe queue saturates → latency climbs → probes fail → more restarts

Sequential with delays ensures each component fully stabilizes (passes readiness probes, finishes initial LIST, stops generating heavy IO) before the next one adds its load.

The cluster survived a full reboot (all VMs restarted) with only a 30% PSI spike lasting 3 minutes — AFTER recovery. The same action during degraded state caused 49-67% sustained for 40+ minutes. The difference is cluster health state at the time of perturbation, not the action itself.
