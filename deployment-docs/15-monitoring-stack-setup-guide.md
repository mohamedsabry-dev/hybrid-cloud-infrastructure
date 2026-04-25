# Monitoring Stack Setup Guide — Prometheus + Grafana + Loki + Alertmanager

Note: This is step 15 in the deployment sequence. Everything below depends on:
  - Kubernetes cluster running (step 9)
  - Flux reconciling (step 10)
  - Vault-K8s trust configured (step 11)
  - ingress-nginx + DNS working (step 13)

Design docs and per-app README files live in:
  kubernetes/dev/deployments/apps/monitoring/
  kubernetes/dev/deployments/apps/alertmanager/
  kubernetes/dev/deployments/apps/logging/

If you face issues during this integration, check:
  troubleshooting/kubernetes/

---

## Overview

Four subsystems compose the monitoring stack. All deploy into the `monitoring`
namespace and are reconciled by Flux:

```
kube-prometheus-stack (HelmRelease)
  ├── Prometheus        scrapes K8s + external nodes, evaluates alert rules
  ├── Grafana           dashboards + Vault-injected admin creds
  ├── Node Exporter     DaemonSet on all nodes including masters
  └── PrometheusRules   custom alerts (ExternalNodeDown, PodCrashLooping, NodeCriticalCPU)

Standalone Alertmanager (StatefulSet)
  └── Vault-templated config → Gmail SMTP → operator email

Loki + Promtail (HelmReleases)
  ├── Loki              log aggregation (single-binary mode)
  └── Promtail          DaemonSet log collector → pushes to Loki
```

Why Alertmanager is standalone (not bundled with kube-prometheus-stack):
  The Helm chart's built-in Alertmanager doesn't support Vault Agent sidecar
  injection for SMTP credentials. A standalone StatefulSet lets Vault template
  the entire alertmanager.yaml at pod startup — no secrets in Git.

---

## Alerting flow

```
Prometheus (scrape 15-30s)
  → alert rule matches (duration threshold)
    → fires to alertmanager.monitoring.svc:9093
      → inhibit rules (critical suppresses warning/info)
      → group by namespace, wait 30s
        → Watchdog → /dev/null
        → everything else → email-alerts receiver
          → Gmail SMTP (creds from Vault)
            → operator inbox (send_resolved: true)
              → repeat every 4h if unresolved
```

---

## Prerequisites

### 1. Vault — store Grafana admin credentials

Run on any Vault node:

```bash
/opt/vault/scripts/vault-pod-setup.sh grafana monitoring grafana-sa
```

Prompts for `admin_user` and `admin_password`. Creates:
  - Secret at `secret/grafana/config`
  - Policy for the `grafana` role
  - K8s auth role binding (grafana-sa in monitoring namespace)

### 2. Vault — store Alertmanager SMTP credentials

```bash
/opt/vault/scripts/vault-pod-setup.sh alertmanager monitoring alertmanager-sa
```

Then manually store the SMTP config:

```bash
vault kv put secret/alertmanager/config \
  smtp_from="<sender@gmail.com>" \
  smtp_password="<gmail-app-password>" \
  alert_email="<recipient@email.com>"
```

### 3. Node Exporter on external hosts

From the Ansible control node:

```bash
cd ~/hybrid-cloud-infrastructure/ansible/dev
ansible-playbook -i inventory/inventory.ini playbooks/common/install_node_exporter.yml
```

Installs node_exporter (port 9100) on:

| Host                 | Dev IP       | Prod IP      | Role       |
|----------------------|--------------|--------------|------------|
| freeipa.lab.local    | 10.0.60.10   | 10.0.50.10   | freeipa    |
| vault1.lab.local     | 10.0.62.10   | 10.0.52.10   | vault      |
| vault2.lab.local     | 10.0.62.11   | 10.0.52.11   | vault      |
| vault3.lab.local     | 10.0.62.12   | 10.0.52.12   | vault      |
| ansible.lab.local    | 10.0.63.10   | 10.0.53.10   | automation |
| local-runner.lab.local | 10.0.63.20 | 10.0.53.20   | automation |
| ex-nginx.lab.local   | 10.0.65.10   | 10.0.55.10   | nginx      |

K8s nodes are NOT in this list — node-exporter DaemonSet from kube-prometheus-stack
covers masters and workers automatically.

---

## Section 1: kube-prometheus-stack (Prometheus + Grafana)

### Chart details

```
Chart:       kube-prometheus-stack
Version:     82.18.0
Repository:  prometheus-community (https://prometheus-community.github.io/helm-charts)
Reconcile:   5m (HelmRelease) / 1h (HelmRepository)
```

### Prometheus

Single instance. Scrapes all ServiceMonitors and PodMonitors cluster-wide
(nilUsesHelmValues disabled on both selectors).

Storage:
  - StorageClass: nfs-retain (NFS CSI → NAS at 10.0.40.120)
  - Size: 20Gi (dev) / 50Gi (prod)
  - Access mode: ReadWriteOnce
  - Mount options: nfsvers=3, nolock, soft, timeo=30, retrans=3

External node scraping configured via additionalScrapeConfigs — targets listed
in the prerequisites table above, scraped every 30s on port 9100.

Alert delivery: pushes to standalone Alertmanager via alertingEndpoints
(alertmanager.monitoring.svc:9093).

### Grafana

Single replica — required because Grafana uses SQLite by default, and multiple
writers on NFS corrupt the database (TS-K8S-037). HA would need an external
PostgreSQL/MySQL backend.

Storage:
  - StorageClass: nfs-retain
  - Size: 5Gi (dev) / 10Gi (prod)
  - Access mode: ReadWriteMany (leftover from the HA attempt, functionally fine)

Ingress:
  - Class: nginx
  - Host: grafana-dev.lab.local (dev) / grafana-prod.lab.local (prod)
  - DNS: Route53 private hosted zone → ex-nginx → ingress-nginx NodePort

Pod anti-affinity: preferred (weight 100), not required. Allows temporary
co-location during rolling updates (TS-K8S-036 fix).

Vault integration (admin credentials):
  - Vault Agent sidecar injects `GF_SECURITY_ADMIN_USER` and
    `GF_SECURITY_ADMIN_PASSWORD` from `secret/data/grafana/config`
  - Custom entrypoint sources `/vault/secrets/grafana-admin` before starting
  - vault-ca Secret (FreeIPA CA cert) for TLS trust to Vault API

Datasources configured in HelmRelease values:
  1. Prometheus (default) — built-in
  2. Loki — `http://loki.monitoring.svc.cluster.local:3100`
  3. Alertmanager — `http://alertmanager.monitoring.svc:9093`

### Node Exporter (DaemonSet)

Runs on all nodes including control-plane (tolerates master/control-plane taints).
Port 9100.

### Custom alert rules

File: `custom-alerts.yaml` (PrometheusRule CRD)

The `release: kube-prometheus-stack` label is required — without it Prometheus
won't load the rules (TS-K8S-041).

| Alert                      | Expression                                             | Duration | Severity |
|----------------------------|--------------------------------------------------------|----------|----------|
| ExternalNodeDown           | `up{job="external-nodes"} == 0`                        | 2m       | critical |
| PodCrashLooping            | `increase(kube_pod_container_status_restarts_total[1h]) > 5` | 5m | warning  |
| KubernetesNodeCriticalCPU  | avg CPU > 95%                                          | 2m       | critical |

---

## Section 2: Standalone Alertmanager

File: `kubernetes/dev/deployments/apps/alertmanager/statefulset.yaml`

```
Image:      quay.io/prometheus/alertmanager:v0.27.0
Type:       StatefulSet (1 replica)
Placement:  control-plane only (survives all-worker-down scenarios)
Storage:    emptyDir (stateless — config comes from Vault at startup)
Resources:  50m-100m CPU, 64Mi-128Mi memory
Ports:      9093 (web/alert ingestion), 9094 (mesh — unused with 1 replica)
```

Vault Agent sidecar templates the full alertmanager.yaml from
`secret/data/alertmanager/config`, injecting smtp_from, smtp_password, and
alert_email at pod startup.

SMTP routing:
  - Gmail SMTP (smtp.gmail.com:587, TLS required)
  - Group by namespace, 30s wait before first notification
  - 4h repeat interval for unresolved alerts
  - Watchdog alerts silenced (routed to "null" receiver)
  - Critical alerts suppress warning/info for same alertname + namespace

---

## Section 3: Loki + Promtail (log aggregation)

File: `kubernetes/dev/deployments/apps/logging/logging.yaml`

### Loki

```
Chart:       loki (grafana helm repo)
Version:     6.29.0
Mode:        SingleBinary (not distributed)
Auth:        disabled
Storage:     filesystem on NFS (nfs-retain)
Size:        50Gi (dev) / 100Gi (prod)
Retention:   168h / 7 days (dev) / 336h / 14 days (prod)
Schema:      TSDB v13, 24h index period
Ingestion:   16 MB/s rate, 32 MB/s burst
```

Non-essential components disabled to reduce footprint: gateway, caches,
self-monitoring, canary, distributed read/write/backend replicas.

### Promtail

```
Chart:       promtail (grafana helm repo)
Version:     6.16.6
Type:        DaemonSet (all nodes including masters)
Push URL:    http://loki:3100/loki/api/v1/push
```

---

## Section 4: Activation

All manifests are Flux-managed. Enable by including the folders in the apps
Kustomization:

```
kubernetes/dev/deployments/apps/kustomization.yaml:
  resources:
    - monitoring       # Prometheus + Grafana + custom alerts
    - alertmanager     # standalone Alertmanager
    - logging          # Loki + Promtail
```

Monitoring kustomization resources:
  - kube-prometheus-stack.yaml (HelmRelease + HelmRepository)
  - service-account.yaml (grafana-sa, pre-created for Vault binding)
  - vault-ca-secret.yaml (FreeIPA CA cert for Vault TLS trust)
  - custom-alerts.yaml (PrometheusRule)

---

## Section 5: Verification

```bash
# 1 — HelmReleases reconciled
kubectl get helmrelease -n monitoring
# expect: kube-prometheus-stack, loki, promtail — all "Ready"

# 2 — pods running
kubectl get pods -n monitoring
# expect: prometheus, grafana, alertmanager, loki, promtail (on every node),
#         node-exporter (on every node)

# 3 — Grafana reachable
# Dev: http://grafana-dev.lab.local
# Prod: http://grafana-prod.lab.local
# Login with Vault-injected admin credentials

# 4 — Prometheus targets
# Grafana → Explore → Prometheus → up
# or: kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090
# then: http://localhost:9090/targets
# expect: external-nodes job showing all 7 hosts UP

# 5 — Alertmanager reachable
kubectl port-forward -n monitoring svc/alertmanager 9093
# http://localhost:9093 — check status and silences

# 6 — Loki receiving logs
# Grafana → Explore → Loki datasource → {namespace="monitoring"} → Run query
# expect: log lines from monitoring pods

# 7 — test alert email (optional)
kubectl -n monitoring exec svc/alertmanager -- wget -qO- --post-data \
  '[{"labels":{"alertname":"TestAlert","severity":"info"},"annotations":{"summary":"Test"}}]' \
  --header="Content-Type: application/json" \
  http://localhost:9093/api/v2/alerts
# expect: email arrives ~30s later
```

---

## Deployment order — where this fits

```
 9  Kubernetes cluster
10  Flux bootstrap
11  Vault-K8s trust                     injector works
12  etcd-backup → Vault → S3            backup pipeline
13  Nginx + ingress-nginx + DNS         traffic in
14  Remediation                         worker self-healing (depends on Alertmanager)
15  Monitoring stack (THIS GUIDE)        observability for everything above
```

Monitoring is last because it observes every other layer. The remediation pod
(step 14) sends alerts to Alertmanager, so Alertmanager should be deployed
before or alongside remediation — the manifests deploy together via Flux.

---

## Storage summary

| Component      | StorageClass | Size (dev/prod) | Access | Mount options                        |
|----------------|-------------|------------------|--------|--------------------------------------|
| Prometheus     | nfs-retain  | 20Gi / 50Gi      | RWO    | nfsvers=3, nolock, soft, timeo=30    |
| Grafana        | nfs-retain  | 5Gi / 10Gi       | RWX    | nfsvers=3, nolock, soft, timeo=30    |
| Loki           | nfs-retain  | 50Gi / 100Gi     | RWO    | nfsvers=3, nolock, soft, timeo=30    |
| Alertmanager   | emptyDir    | —                 | —      | stateless, no persistence            |
| Promtail       | —           | —                 | —      | DaemonSet, no storage                |
| Node Exporter  | —           | —                 | —      | DaemonSet, no storage                |

All NFS-backed PVCs use the NAS at 10.0.40.120, share `/volume1/k8s-dev` (dev)
or `/volume1/k8s-prod` (prod), with Retain reclaim policy.

---

## File reference

| Component                     | Path                                                          |
|-------------------------------|---------------------------------------------------------------|
| Prometheus + Grafana HelmRelease | kubernetes/dev/deployments/apps/monitoring/kube-prometheus-stack.yaml |
| Custom alert rules            | kubernetes/dev/deployments/apps/monitoring/custom-alerts.yaml  |
| Grafana service account       | kubernetes/dev/deployments/apps/monitoring/service-account.yaml|
| Vault CA secret               | kubernetes/dev/deployments/apps/monitoring/vault-ca-secret.yaml|
| Monitoring kustomization      | kubernetes/dev/deployments/apps/monitoring/kustomization.yaml  |
| First-deploy runbook          | kubernetes/dev/deployments/apps/monitoring/setup-guide.txt     |
| Alertmanager StatefulSet      | kubernetes/dev/deployments/apps/alertmanager/statefulset.yaml  |
| Alertmanager Service          | kubernetes/dev/deployments/apps/alertmanager/service.yaml      |
| Alertmanager ServiceAccount   | kubernetes/dev/deployments/apps/alertmanager/serviceaccount.yaml|
| Loki + Promtail HelmReleases  | kubernetes/dev/deployments/apps/logging/logging.yaml           |
| Monitoring namespace          | kubernetes/dev/deployments/infrastructure/namespaces/namespaces.yaml |
| NFS StorageClass              | kubernetes/dev/deployments/infrastructure/storage/storageclass.yaml |
| Node exporter playbook        | ansible/dev/playbooks/common/install_node_exporter.yml         |

Prod mirror: same paths under `kubernetes/prod/`, `ansible/prod/`.

---

## Troubleshooting

| Symptom | Likely cause |
|---------|--------------|
| Grafana pod CrashLoopBackOff | Vault secret missing or vault-ca Secret not deployed. Check vault-agent-init logs |
| Grafana dashboards disappear after restart | SQLite corruption from multiple writers. Confirm replicas=1 (TS-K8S-037) |
| Grafana stuck during rolling update | Anti-affinity blocking scheduling. Should be preferred, not required (TS-K8S-036) |
| Custom alerts not firing | PrometheusRule missing `release: kube-prometheus-stack` label (TS-K8S-041) |
| Loki datasource health check fails | Loki version mismatch with Grafana. Ensure loki chart 6.x (Loki 3.x), not deprecated loki-stack (TS-K8S-020) |
| External nodes show DOWN in Prometheus | node_exporter not installed or firewall blocking port 9100 |
| Alertmanager not sending emails | SMTP creds wrong in Vault. Check `vault kv get secret/alertmanager/config` |
| Prometheus PVC shows NFSv4.2 | PV provisioned before nfsvers=3 added to StorageClass. Functionally fine, cosmetic only (TS-K8S-048) |
| Alertmanager pod stuck in Init | vault-agent can't reach Vault. Check vault-ca Secret + Vault role binding |

---

## Known limitations

- Grafana is single-replica (SQLite). HA requires external database — not implemented.
- Alertmanager is stateless (emptyDir). Alert history lost on pod restart.
  Config survives because Vault re-injects on every startup.
- Prometheus PVC was provisioned on NFSv4.2 before StorageClass pinned v3.
  Retrofit needs PV delete + data migration (TS-K8S-048).
- No Grafana dashboards-as-code yet. Dashboards are manually created in the UI
  and persist on the NFS PVC.
