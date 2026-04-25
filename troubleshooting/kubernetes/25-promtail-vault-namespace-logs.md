# TS-K8S-025 | 2026-04-11 | SUSPENDED
# Originally identified during DR Task 1 pod kill testing.
# Partially investigated 2026-04-20 — symptoms confirmed, root cause not yet found.
_____________________________________________________________________

[Info]
Domain: Kubernetes / Monitoring
Sub-techs: Promtail, Loki, Vault namespace, log collection, DaemonSet,
           kubernetes_sd_configs, kube-proxy, CoreDNS
Environment: DEV k8s-dev cluster
Re-opened: No

_____________________________________________________________________

[Issue Description]
Promtail not collecting logs from Vault namespace. Also confirmed not collecting
logs from kube-proxy or CoreDNS. Only affects certain namespaces/pods — other
namespaces (apps, database, monitoring) work fine.

Originally observed during DR Task 1 pod kill testing on 2026-04-11.

_____________________________________________________________________

[Analysis]

# Confirmed Findings (2026-04-20 investigation)

## What works:
  - kubectl logs for vault pods — works fine from CLI
  - Prometheus metrics for vault pods — cadvisor, kube-state-metrics all present
  - Promtail DaemonSet runs on ALL 6 nodes including all 3 masters
  - Vault pods are on master1 and master3, Promtail pods on those nodes confirmed
  - Log files exist on disk at /var/log/pods/ on correct masters
  - Promtail RBAC — ClusterRole has get/list/watch on pods cluster-wide
  - Promtail config — no namespace drops, no filtering rules
  - Loki — reachable and healthy from masters

## What doesn't work:
  - Promtail /targets endpoint on master1 returns 0 vault targets
  - Loki shows no logs for {namespace="vault"} (historical)
  - Loki shows no logs for kube-proxy or CoreDNS either
  - Same pattern: pods that are always running, low log volume

## Key evidence:

Command: kubectl exec -n monitoring promtail-vm2k5 -- ls /var/log/pods/ | grep vault

Output:
```
vault_vault-agent-injector-5877589b57-fvdt6_4e462d5f-6b97-44f1-85c3-251a6f7e2542
```

Command: kubectl exec -n monitoring promtail-vm2k5 -- wget -qO- http://localhost:3101/targets 2>/dev/null | grep -c "vault"

Output:
```
0
```

Log files ARE readable by Promtail:
```
kubectl exec -n monitoring promtail-vm2k5 -- cat /var/log/pods/vault_.../sidecar-injector/18.log | tail -3
2026-04-20T21:10:44 stderr F [INFO] handler: Request received: Method=POST URL=/mutate?timeout=30s
2026-04-20T22:56:55 stderr F [INFO] handler: Request received: Method=POST URL=/mutate?timeout=30s
2026-04-20T22:59:34 stderr F [INFO] handler: Request received: Method=POST URL=/mutate?timeout=30s
```

/var/log/containers/ does NOT exist in the Promtail pod (not mounted).

## Partial recovery observed:

After CSI NFS rollout (which restarted all Promtail DaemonSet pods), 2 vault log
lines appeared in Loki — both from ~22:56-22:59. These were /mutate requests
triggered by debug pods we ran during investigation, not historical logs.

Positions file showed Promtail started tracking vault log files:
```
sidecar-injector/17.log: "444"
sidecar-injector/18.log: "2560"
```

But kube-proxy and CoreDNS still show nothing in Loki even after the restart.

## Eliminated suspects:
  [x] Namespace exclusion in Promtail config — no drops found
  [x] RBAC permission issue — ClusterRole grants full pod access
  [x] Vault pods on nodes without Promtail — confirmed Promtail runs on same masters
  [x] Log files not on disk — confirmed present and readable
  [x] Loki unreachable — Loki healthy and receiving other namespace logs
  [x] Static pod __path__ mismatch — vault-agent-injector is not a static pod

## Remaining suspects to investigate:
  [ ] Promtail kubernetes_sd target discovery not picking up vault/kube-proxy/CoreDNS pods
  [ ] __path__ glob pattern mismatch for these specific pods
  [ ] Promtail watching from API but silently dropping targets with no local file match
      (race condition between discovery and file existence check)
  [ ] NetworkPolicy in vault namespace blocking API discovery
  [ ] Promtail positions file corruption or stale entries preventing re-read

_____________________________________________________________________

[Final Root Cause]
Not yet determined.

_____________________________________________________________________

[Final Solution]
Pending investigation.

Verified: No

_____________________________________________________________________

[Risk Level] MEDIUM

Vault agent injector logs are invisible to Grafana/Loki. During DR events or
incidents, operators cannot see vault webhook activity through the monitoring
stack — must fall back to kubectl logs. Same blind spot for kube-proxy and CoreDNS.

_____________________________________________________________________

[References]
- disaster-recovery/app-pod-kill-wordpress-mariadb-injector.md (where issue was first observed)
- TS-K8S-047 — CSI rollout that restarted Promtail and briefly showed vault logs

_____________________________________________________________________

[Draft Notes]
Next steps when resuming:
  [ ] Check NetworkPolicy in vault namespace: kubectl get networkpolicy -n vault
  [ ] Deep inspect Promtail target discovery: full /targets output, not just grep
  [ ] Compare working namespace (apps) vs broken (vault) in Promtail targets
  [ ] Check if Promtail has node affinity filtering in its SD config
  [ ] Test: manually restart single Promtail pod on master1, watch /targets for vault
  [ ] Check Loki ingestion limits / rate limiting
