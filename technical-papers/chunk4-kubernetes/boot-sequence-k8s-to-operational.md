Boot Sequence Part 2 — K8s Cluster to Fully Operational Platform (Summary Trace)
==================================================================================

pre-trace (already running from Part 1):
  Proxmox host + NFS + FreeIPA (DNS/Kerberos) + Vault cluster (auto-unsealed)
    → K8s masters x3 + workers x3 booted, kubelet running, no CNI yet

etcd stabilizes → Raft quorum (2/3) → cluster state available
  → kube-apiserver accepts requests on VIP :16443
    → scheduler + controller-manager start control loops
      → kubelets register nodes → NotReady (no CNI)

→ Calico CNI DaemonSet deploys on all nodes
  → pod CIDR assigned (10.245.0.0/16) → BGP peering established
    → nodes transition NotReady → Ready

→ CoreDNS pods start on masters (TS-K8S-053: 94s vs 3m35s on workers)
  → cluster DNS functional: *.svc.cluster.local + lab.local → FreeIPA

→ Flux controllers start → source-controller clones git repo
  → infrastructure Kustomization reconciles:
    → namespaces → CRDs → CSI-NFS → vault-agent-injector → ingress-nginx → prometheus stack
      → healthCheck: vault-agent-injector must be Ready

→ vault-agent-injector reaches Vault cluster (vault.lab.local:8200)
  → registers MutatingWebhookConfiguration → reports Ready
    → infrastructure Kustomization Ready → apps Kustomization unblocked

→ apps Kustomization reconciles:
  → Alertmanager + Loki/Promtail + event-exporter + etcd-backup
    + remediation + WordPress/MariaDB + nginx
      → each Vault-annotated pod: init container → K8s auth → Vault token → secrets → start

→ Prometheus scrapes all targets (30s interval, ServiceMonitor discovery)
  → Promtail DaemonSet pushes logs to Loki from /var/log/pods/
    → Grafana connects: Prometheus + Loki + Alertmanager

→ remediation pod: 300s startup delay → begins health monitoring
→ etcd-backup CronJob: if missed schedule, fires with 6 retries (TS-K8S-057)
→ all 3 alert paths operational (Prometheus/remediation/host scripts → Gmail)

→ platform fully operational (~17 min total from power button)
