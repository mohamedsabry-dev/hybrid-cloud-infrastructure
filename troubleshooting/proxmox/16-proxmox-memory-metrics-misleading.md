# TS-PVE-016: Proxmox Memory Metrics Misleading for VM Monitoring

**Date:** 2026-04-11
**Status:** DOCUMENTED (Informational)
**Severity:** Low (No actual issue, just misleading metrics)
**Environment:** Both (Dev + Prod)

---

## Summary

Proxmox VM memory metrics show ~97% usage for prod masters and ~85% for dev masters, but actual memory usage inside VMs is much lower (~54% and ~74% respectively). This is because Linux uses free RAM for disk cache/buffers, which Proxmox counts as "used."

---

## Symptoms

- Proxmox UI shows master VMs at 85-97% memory usage
- Alerts may trigger for "high memory" when system is healthy
- Misleading data for capacity planning

---

## Investigation

### Proxmox Reported (Misleading)

| Environment | VM RAM | Proxmox Shows |
|-------------|--------|---------------|
| Prod Master | 4 GB | ~97% used |
| Dev Master | 2.5 GB | ~85% used |

### Actual Usage (Accurate)

**Prod Master (from Grafana/Prometheus):**
- Total: 4 GiB
- Actual Used: ~2.2 GiB (54.5%)
- Cache/Buffers: ~1.5 GiB
- Available: ~1.7 GiB

**Dev Master (from Grafana/Prometheus):**
- Total: ~2 GiB
- Actual Used: ~1.5 GiB (74.1%)
- Cache/Buffers: ~0.5 GiB
- Available: smaller headroom

**Prod Master (from `free -h` on node):**
```
               total        used        free      shared  buff/cache   available
Mem:           3.6Gi       1.9Gi       133Mi        44Mi       1.8Gi       1.7Gi
Swap:             0B          0B          0B
```

**Top Memory Consumers (prod master1):**
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

---

## Root Cause

**Linux Memory Management:**
- Linux uses all available RAM for disk cache/buffers
- This improves performance (faster disk reads from cache)
- Cache is **immediately released** when applications need memory
- Proxmox reports `used + cached` as "used memory"
- This is **normal and healthy behavior**

**Why Proxmox Metrics Are Misleading:**
- Proxmox uses `qemu-guest-agent` to read `/proc/meminfo`
- It reports `MemTotal - MemFree` as "used"
- Does NOT subtract `Buffers + Cached` (reclaimable memory)
- Result: Healthy system appears to have high memory usage

---

## Resolution

**No action needed** — the system is healthy.

### Correct Metrics to Monitor

Use these metrics from Prometheus/node-exporter instead:

```promql
# Actual memory usage (excludes cache)
node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes

# Memory usage percentage (accurate)
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# DO NOT use this (misleading like Proxmox):
node_memory_MemTotal_bytes - node_memory_MemFree_bytes
```

---

## Recommendations

### 1. Do NOT Trust Proxmox Memory Metrics for Alerting

Proxmox memory metrics are misleading and should not be used for:
- CloudWatch integration
- Alerting thresholds
- Capacity planning decisions

### 2. Use Prometheus for Monitoring Integration

When integrating with AWS CloudWatch or other monitoring systems:
- Export metrics from Prometheus, NOT from Proxmox API
- Use `node_memory_MemAvailable_bytes` for accurate memory
- Use `node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes` for used memory

### 3. Future CloudWatch Integration Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌────────────────┐
│ node-exporter   │────▶│ Prometheus       │────▶│ CloudWatch     │
│ (accurate data) │     │ (central store)  │     │ (via exporter) │
└─────────────────┘     └──────────────────┘     └────────────────┘

NOT this:
┌─────────────────┐     ┌────────────────┐
│ Proxmox API     │────▶│ CloudWatch     │  ← MISLEADING DATA
│ (inflated mem)  │     │                │
└─────────────────┘     └────────────────┘
```

### 4. Install Metrics Server for kubectl top

Currently missing — install to enable `kubectl top nodes` and `kubectl top pods`:
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

---

## Key Takeaways

| Metric Source | Memory % | Accurate? | Use For |
|---------------|----------|-----------|---------|
| Proxmox UI | 85-97% | NO | Visual only |
| Grafana (node-exporter) | 54-74% | YES | Alerting, CloudWatch |
| `free -h` (available) | accurate | YES | SSH debugging |

---

## Related

- [TS-K8S-025](../kubernetes/25-promtail-vault-namespace-logs.md) — Promtail not scraping vault namespace (TODO)
- Future: CloudWatch integration via Prometheus remote-write

---

## Notes

- **This is not a bug** — it's how Linux memory management works
- Proxmox showing high memory is actually a sign of efficient cache usage
- Only worry if `available` memory approaches zero AND swap is being used
- Current state is healthy: 1.7 GiB available on prod masters
