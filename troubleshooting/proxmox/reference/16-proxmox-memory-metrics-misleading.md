# TS-PVE-016 | 2026-04-11 | DOCUMENTED
_____________________________________________________________________

[Info]
Domain: Proxmox VE / Monitoring
Sub-techs: qemu-guest-agent, /proc/meminfo, Linux memory cache, Prometheus
Environment: DEV & PROD Proxmox servers
Re-opened: No

_____________________________________________________________________

[Issue Description]
Proxmox VM memory metrics show ~97% usage for prod masters and ~85% for dev
masters, but actual memory inside VMs is much lower (~54% and ~74%). This is
normal Linux behavior — not a real issue, but misleading for alerting and
capacity planning.

_____________________________________________________________________

[Analysis]

# Step 1: Proxmox reported vs actual

| Environment | VM RAM | Proxmox Shows | Actual Used |
|-------------|--------|---------------|-------------|
| Prod Master | 4 GB | ~97% | ~54% (2.2 GiB) |
| Dev Master | 2.5 GB | ~85% | ~74% (1.5 GiB) |

# Step 2: Verified from inside a prod master

```
               total        used        free      shared  buff/cache   available
Mem:           3.6Gi       1.9Gi       133Mi        44Mi       1.8Gi       1.7Gi
Swap:             0B          0B          0B
```

1.7 GiB available — system is healthy. The 1.8 GiB in buff/cache is reclaimable.

# Step 3: Top memory consumers (prod master1)

```
Process                    RSS (MB)   %MEM
kube-apiserver             592        15.8%
etcd                       156        4.1%
kubelet                    109        2.9%
promtail                   106        2.8%
calico-node (total)        ~400       ~11%
containerd                 86         2.3%
coredns                    71         1.8%
kube-controller-manager    68         1.8%
kube-scheduler             63         1.6%
kube-proxy                 52         1.3%
```

_____________________________________________________________________

[Final Root Cause]
Proxmox uses `qemu-guest-agent` to read `/proc/meminfo` and reports
`MemTotal - MemFree` as "used." It does NOT subtract `Buffers + Cached`
(reclaimable memory). Linux uses all free RAM for disk cache, so Proxmox
always shows inflated numbers. This is normal behavior.

_____________________________________________________________________

[Final Solution]

No fix needed — the system is healthy.

For accurate monitoring, use Prometheus/node-exporter metrics instead of
Proxmox API:

```promql
# Actual memory usage (excludes cache)
node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes

# Memory usage percentage (accurate)
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100
```

| Metric Source | Memory % | Accurate? | Use For |
|---------------|----------|-----------|---------|
| Proxmox UI | 85-97% | NO | Visual only |
| Grafana (node-exporter) | 54-74% | YES | Alerting, CloudWatch |
| `free -h` (available) | accurate | YES | SSH debugging |

Verified: Yes — Grafana dashboards show correct memory usage.

_____________________________________________________________________

[Risk Level] LOW

No actual issue. Only risk is alerting on false positives if using Proxmox
metrics for monitoring integration.

_____________________________________________________________________

[References]
- TS-K8S-025 — Promtail not scraping vault namespace
