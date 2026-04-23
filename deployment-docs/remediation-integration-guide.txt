# Remediation Integration Guide (DEV) — Proxmox API + K8s + Alertmanager

Note: This integration runs after Vault-K8s integration (step 10) and Nginx (step 11)
are operational. The "why behind the design" and the Python script live in:
  kubernetes/dev/deployments/apps/remediation/DESIGN.md
The one-time provisioning log from the first deploy lives in:
  kubernetes/dev/deployments/apps/remediation/SETUP.md

If you face issues during this integration, check:
  troubleshooting/kubernetes/
  troubleshooting/vault/

---

## Overview

This guide wires up three subsystems so the worker self-healing pod can do its job:
Proxmox API (acts on VMs), Kubernetes (hosts the pod + provides node status + injects
secrets), and Alertmanager (forwards remediation events to email). Every configuration
file referenced below already exists in the repo — this guide is the order in which
to deploy them and the commands to verify each hop.

Integration chain:

```
remediation pod (K8s master, 1 replica)
  │
  ├── watches:   K8s API → nodes/ (get/list/watch via remediation-sa)
  │
  ├── acts via:  Proxmox API at https://<proxmox-host>:8006
  │              auth:  token k8s-pve@pve!remediation
  │              creds: /vault/secrets/proxmox-creds (injected by vault-agent sidecar)
  │
  └── alerts:    http://alertmanager.monitoring.svc:9093/api/v2/alerts
                 (Alertmanager → SMTP receiver → operator email)
```

---

## Prerequisites

Before starting this integration:

- FreeIPA deployed and running. All nodes DNS-resolvable, SSH-reachable as super_bot.
- Vault cluster up + unsealed. K8s auth method configured.
  See: vault-k8s-integration-guide.txt
- Kubernetes cluster running (3 masters + 3 workers).
  Dev node-to-VMID map:  k8s-worker1 → 1020, k8s-worker2 → 1021, k8s-worker3 → 1022
- Flux reconciling kubernetes/dev/deployments/apps/ and infrastructure/.
- kube-prometheus-stack deployed. Alertmanager on master with emptyDir volume,
  SMTP receiver configured, reachable at alertmanager.monitoring.svc:9093.
- NAS reachable from Proxmox for vzdump backups (nas-dev-data / nas-prod-data).
  Backups of worker VMIDs exist on the NAS.

---

## Section 1: Open the Proxmox API path from master VLAN

The remediation pod runs on a K8s master. Masters sit in VLAN 61 (dev) / 51 (prod).
Proxmox management listens on 8006. MikroTik default rules block cross-VLAN, so an
explicit allow rule is needed. Workers have NO route to Proxmox by design.

Add these rules on the MikroTik (one-time, both envs):

  /ip firewall filter add chain=forward \
    src-address=10.0.61.0/24 dst-address=10.0.5.110 protocol=tcp dst-port=8006 \
    action=accept comment="Allow dev K8s masters -> dev Proxmox API" place-before=13

  /ip firewall filter add chain=forward \
    src-address=10.0.51.0/24 dst-address=10.0.5.100 protocol=tcp dst-port=8006 \
    action=accept comment="Allow prod K8s masters -> prod Proxmox API" place-before=13

The `place-before=13` puts the allow rule above the default cross-VLAN drop.

Router config reference:
  network/router/mikrotik/phase2-dev-services.rsc

Verify from a master:

  ssh super_bot@10.0.61.10
  curl -k https://10.0.5.110:8006/api2/json/version
  # expect: {"data":{"release":"...","version":"..."}}

---

## Section 2: Create the Proxmox API user and token

Run on the Proxmox host (dev = pve-dev, prod = pve-prod):

  pveum user add k8s-pve@pve --comment "Kubernetes remediation service account"
  pveum acl modify / --users k8s-pve@pve --roles Administrator
  pveum user token add k8s-pve@pve remediation --privsep 0 --expire 0

The final command prints full-tokenid (e.g. k8s-pve@pve!remediation) and value
(the secret). Record both — used in Section 3.

Known limitation: token currently has Administrator role. Scope-down to
VM.PowerMgmt + VM.Backup + VM.Audit on specific VMIDs is planned but not done.
See: kubernetes/dev/deployments/apps/remediation/DESIGN.md

---

## Section 3: Store the Proxmox token in Vault + authorize the pod

From any host with the vault CLI + Kerberos auth:

  vault login -method=ldap username=sabry

  vault kv put secret/remediation/config \
    PROXMOX_HOST="https://10.0.5.110:8006" \
    PROXMOX_TOKEN_ID="k8s-pve@pve!remediation" \
    PROXMOX_TOKEN_SECRET="<value from Section 2>"

  vault policy write remediation-policy - <<EOF
  path "secret/data/remediation/config" {
    capabilities = ["read"]
  }
  EOF

  vault write auth/kubernetes/role/remediation \
    bound_service_account_names="remediation-sa" \
    bound_service_account_namespaces="remediation" \
    policies="remediation-policy" \
    ttl="1h"

This can also be done via the helper script — same pattern every app uses:
  kubernetes/docs/vault-pod-setup.sh

---

## Section 4: Deploy the K8s-side resources via Flux

All manifests for the remediation pod are in:
  kubernetes/dev/deployments/apps/remediation/

Files (in this folder):
  namespace.yaml             → dedicated "remediation" namespace
                               (Vault injector webhook explicitly permits it —
                                kube-system is denied by default, TS-K8S-017)
  priorityclass.yaml         → self-healing-critical PriorityClass (value 1000000)
  remediation-auth-sa.yaml   → remediation-sa + read-only ClusterRole on nodes
  vault-ca-secret.yaml       → IPA CA cert for vault-agent TLS trust
  configmap.yaml             → the Python remediation script (source of truth)
  deployment.yaml            → 1-replica Deployment on master with Vault annotations
  kustomization.yaml         → stitches them all together for Flux

Deployment happens automatically when Flux reconciles the apps Kustomization.

Key annotations already set in the committed deployment.yaml:
  - vault.hashicorp.com/agent-inject:          "true"
  - vault.hashicorp.com/role:                  "remediation"
  - vault.hashicorp.com/tls-secret:            "vault-ca"
  - vault.hashicorp.com/agent-inject-secret-proxmox-creds:
        secret/data/remediation/config
  - config-version: "N"   (bump this annotation whenever configmap.yaml changes;
                           K8s doesn't restart pods on ConfigMap changes otherwise)

Pod placement (already in deployment.yaml):
  - nodeSelector:      node-role.kubernetes.io/control-plane=""
  - toleration:        node-role.kubernetes.io/control-plane NoSchedule
  - priorityClassName: self-healing-critical
  - replicas:          1
  - command:           ["python", "-u", "/scripts/remediation.py"]
                       (-u = unbuffered; without it, kubectl logs shows nothing
                        until the pod exits)

Container image (rebuild when debugging tools need updating):
  kubernetes/docker-images/remediation/Dockerfile
  Includes: python + kubernetes client + proxmoxer + requests + procps +
           iputils-ping + traceroute + dnsutils + jq + netcat-openbsd +
           openssh-client + vim-tiny

---

## Section 5: Alertmanager-side setup

Alertmanager is part of the monitoring stack. Two requirements for remediation
alerts to turn into emails:

  1. Alertmanager reachable at http://alertmanager.monitoring.svc:9093
     (the Service name hardcoded in configmap.yaml). This is the default name
     created by the kube-prometheus-stack Helm chart.

  2. Alertmanager SMTP receiver configured to email the operator. Config lives
     in the monitoring stack's HelmRelease values:
       kubernetes/dev/deployments/apps/monitoring/helm-release.yaml

No per-alert rule is needed. The remediation script sends alerts with:
  labels.alertname = RemediationAction
  labels.severity  = warning | critical | info
which the default receiver picks up.

Alertmanager placement (same reasoning as remediation: master-only, stateless):
  - nodeSelector:      node-role.kubernetes.io/control-plane=""
  - toleration:        control-plane NoSchedule
  - volumes:           emptyDir (NOT a PVC — NFS CSI doesn't run on masters)
  - priorityClassName: self-healing-critical

See DESIGN.md for why Alertmanager is on master + stateless.

---

## Section 6: Verify the integration (pod-level)

After Flux reconciles, run these in order:

  # 1 — pod running with vault-agent sidecar
  kubectl -n remediation get pods
  # expect: remediation-xxxxxxxxx-yyyyy   2/2   Running   0   Xm
  # the 2/2 means vault-agent sidecar is injected and running

  # 2 — Vault secret reached the pod
  kubectl -n remediation exec deploy/remediation -- cat /vault/secrets/proxmox-creds
  # expect: 3 lines: PROXMOX_HOST=, PROXMOX_TOKEN_ID=, PROXMOX_TOKEN_SECRET=

  # 3 — script started and is watching nodes
  kubectl -n remediation logs deploy/remediation --tail=30
  # expect:
  #   Remediation service starting...
  #   Monitoring nodes: ['k8s-worker1.lab.local', 'k8s-worker2.lab.local', 'k8s-worker3.lab.local']
  #   Check interval: 300s
  #   Waiting 300s before first health check (cluster stabilization)...
  #   --- Health check at ... ---
  #   k8s-worker1.lab.local: Healthy
  #   k8s-worker2.lab.local: Healthy
  #   k8s-worker3.lab.local: Healthy

  # 4 — Proxmox API reachable from inside the pod
  kubectl -n remediation exec deploy/remediation -- \
    curl -k -sS https://10.0.5.110:8006/api2/json/version \
    -H "Authorization: PVEAPIToken=k8s-pve@pve!remediation=<token>"
  # expect: 200 OK with Proxmox version JSON

  # 5 — Alertmanager reachable from inside the pod (DNS + HTTP)
  kubectl -n remediation exec deploy/remediation -- \
    curl -sS http://alertmanager.monitoring.svc:9093/api/v1/status
  # expect: 200 OK with Alertmanager status JSON

  # 6 — manual alert test (optional — fires a test email)
  kubectl -n remediation exec deploy/remediation -- \
    curl -s -X POST http://alertmanager.monitoring.svc:9093/api/v2/alerts \
    -H "Content-Type: application/json" \
    -d '[{"labels":{"alertname":"RemediationTest","node":"test","action":"test","severity":"info"},"annotations":{"summary":"Test alert"}}]'
  # expect: 200 OK, email arrives ~30s later

---

## Section 7: End-to-end behavior test (controlled)

This test deliberately takes a worker NotReady and observes the remediation loop.
Run only after Section 6 passes cleanly.

  # 1. On Proxmox, stop a worker VM (pick worker3 to minimize impact):
  ssh super_bot@10.0.5.110
  qm stop 1022   # dev worker3

  # 2. From the Ansible host or Mac Mini, tail the remediation logs:
  kubectl -n remediation logs -f deploy/remediation

  # 3. Within ~5-7 minutes, expect:
  #   --- Health check at ... ---
  #   k8s-worker3.lab.local: UNHEALTHY! (Node NotReady)
  #   --- Remediating 1 unhealthy node(s) ---
  #   [Attempt 1] Remediating k8s-worker3.lab.local (VM 1022)
  #     -> VM 1022 status: stopped
  #     -> VM 1022 is stopped, starting instead of rebooting
  #     -> Starting VM 1022
  #     -> Alert sent: reboot - initiated

  # 4. Worker3 comes back Ready within another ~2-3 min:
  #   --- Health check at ... ---
  #   k8s-worker3.lab.local: Recovered! Resetting counter.
  #     -> Alert sent: recovery - node is healthy again

  # 5. Check email — 2 messages (reboot initiated, recovery)

If the test fails at any hop, rerun the Section 6 verification to narrow down
which layer is broken.

---

## Deployment Order — where this fits

This is step 14 in the README.md sequence:

  7  FreeIPA                                           foundation
  8  Vault                                             identity-based secrets
  9  Kubernetes                                        cluster itself
  10 Flux bootstrap                                    GitOps reconciling everything below
  11 Vault <-> K8s trust                               injector works
  12 etcd-backup -> Vault -> S3                        backup via STS, no long-lived AWS keys
  13 Nginx + ingress-nginx + DNS                       traffic in
  14 Remediation (THIS GUIDE)                          worker self-healing

Remediation is last because every dependency above it must be up:
  - IPA for Proxmox hostname resolution
  - Vault to hold the Proxmox token
  - K8s to host the pod
  - Monitoring stack to receive alerts
  - Workers already provisioned with backup history on NAS

---

## File Reference

| Component                          | Path                                                                |
|------------------------------------|---------------------------------------------------------------------|
| Design + reasoning                 | kubernetes/dev/deployments/apps/remediation/DESIGN.md               |
| Folder README                      | kubernetes/dev/deployments/apps/remediation/README.md               |
| One-time provisioning log          | kubernetes/dev/deployments/apps/remediation/SETUP.md                |
| Remediation script (Python)        | kubernetes/dev/deployments/apps/remediation/configmap.yaml          |
| Deployment spec                    | kubernetes/dev/deployments/apps/remediation/deployment.yaml         |
| Priority class                     | kubernetes/dev/deployments/apps/remediation/priorityclass.yaml      |
| ServiceAccount + RBAC              | kubernetes/dev/deployments/apps/remediation/remediation-auth-sa.yaml|
| Namespace                          | kubernetes/dev/deployments/apps/remediation/namespace.yaml          |
| Vault-CA Secret (IPA CA cert)      | kubernetes/dev/deployments/apps/remediation/vault-ca-secret.yaml    |
| Kustomize wrapper                  | kubernetes/dev/deployments/apps/remediation/kustomization.yaml      |
| Container image                    | kubernetes/docker-images/remediation/Dockerfile                     |
| Monitoring stack (Alertmanager)    | kubernetes/dev/deployments/apps/monitoring/helm-release.yaml        |
| MikroTik firewall config           | network/router/mikrotik/phase2-dev-services.rsc                     |
| Helper script (Vault policy/role)  | kubernetes/docs/vault-pod-setup.sh                                  |
| Vault injection pattern            | vault-k8s-integration-guide.txt                                     |
| Vault overview (layer map)         | vault-overview.md                                                   |
| DR test for this system            | disaster-recovery/worker-2of3-down.md                               |
| TS case — vault injection ns issue | troubleshooting/kubernetes/17-vault-injection-system-namespace-denied.md |

Prod mirror: same paths under kubernetes/prod/, ansible/prod/.

---

## IP Reference

| Component               | Dev            | Prod           |
|-------------------------|----------------|----------------|
| Proxmox host            | 10.0.5.110     | 10.0.5.100     |
| K8s master VLAN         | 10.0.61.0/24   | 10.0.51.0/24   |
| Worker VMIDs            | 1020-1022      | 1020-1022      |
| NFS backup storage      | nas-dev-data   | nas-prod-data  |
| Restore target storage  | local-lvm      | local-lvm      |

---

## Troubleshooting

| Symptom                                         | Likely cause / check                                            |
|-------------------------------------------------|-----------------------------------------------------------------|
| Pod stuck in Init:0/2                           | vault-agent-init can't reach Vault. Check vault-ca Secret + Vault role binding |
| Pod Running 2/2 but logs show "NameError"       | Script bug after last ConfigMap edit. Check configmap.yaml, bump config-version |
| "Failed to get VM 1022 status"                  | Proxmox token expired/revoked/wrong. Re-check Vault secret      |
| "hostname lookup 'pve' failed"                  | PROXMOX_NODE hardcoded to wrong name. Should be pve-dev / pve-prod |
| Alerts not arriving in email                    | SMTP receiver misconfigured in Alertmanager values. Check monitoring helm-release |
| 500 Internal Server Error "VM not running"      | Known — reset_vm now status-checks before acting (fixed)        |
| "admission webhook vault.hashicorp.com denied"  | Trying to deploy in kube-system. Use the dedicated remediation ns (TS-K8S-017) |
| Two remediation cycles from one manual restart  | Manual restart looks like NotReady. Pre-action verify not yet in live script |
| Counter stuck at "max attempts reached"         | Node never recovered. Fix the node, delete the remediation pod to reset in-memory counter |

---

## Known Limitations (pointer)

Full list lives in: kubernetes/dev/deployments/apps/remediation/DESIGN.md

Short version:
  - Proxmox token still has Administrator role (scope-down planned)
  - Counter is per-process, doesn't persist across pod restarts
  - No /metrics endpoint (no Grafana dashboard yet)
  - No Descheduler (post-recovery pod distribution stays uneven)
