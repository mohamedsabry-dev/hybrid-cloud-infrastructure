K8s Pod Creation — Manifest to Vault-Injected Running App (Summary Trace)
==========================================================================

pre-trace (one-time setup):
  K8s ↔ Vault trust: K8s API endpoint + CA cert + vault-auth SA token + issuer
    → written into vault auth/kubernetes/config
  per-app: KV secret + read-only policy + k8s auth role (bound to SA + namespace)

Flux detects commit → kustomize build → manifest sent to kube-apiserver
  → API server gates: Authentication (who?) → Authorization/RBAC (allowed?)
    → Admission Control (schema valid? webhooks pass?)
      → objects land in etcd: Namespace → SA → ConfigMap → Secret (vault-ca)
        → PVC (NFS CSI) → Service (ClusterIP) → Ingress → Deployment

→ controller manager sees Deployment → creates ReplicaSet → creates Pod objects
  → pods in etcd as specs only (status: Pending, no node, no containers)

→ API server fires MutatingWebhooks on each Pod before saving final spec
  → vault-agent-injector reads annotations (role, secret path, template, TLS)
    → mutates spec: adds vault-agent-init (init), vault-agent (sidecar),
      emptyDir at /vault/secrets/, vault-ca mount at /vault/tls/
        → mutated spec saved to etcd

→ scheduler sees unassigned pods → filters (resources, taints, affinity)
  → scores remaining → writes node name → saved to etcd (status: Scheduled)

→ kubelet on assigned node reads pod spec → writes /etc/resolv.conf
  → containerd pulls images → starts init containers in order

→ vault-agent-init starts → reads SA JWT from /var/run/secrets/
  → TLS handshake 1: vault-agent → Vault (vault.lab.local:8200)
    → Vault cert verified by FreeIPA CA (from vault-ca Secret at /vault/tls/)
      → POST /v1/auth/kubernetes/login { role, jwt }
        → Vault extracts SA+NS from JWT, needs verification

→ TLS handshake 2: Vault → K8s API (10.0.51.100:16443, TokenReview)
  → K8s cert verified by K8s CA (from one-time trust setup)
    → Vault presents vault-auth token → sends TokenReview
      → K8s confirms: "wordpress-sa in apps namespace"
        → Vault matches role → issues temp token with scoped policy

→ vault-agent-init uses token → GET /v1/secret/data/wordpress/config
  → renders Go template → writes /vault/secrets/db-creds → exits 0

→ wait-for-dependency init container (if present)
  → resolves dependency service via CoreDNS → nc -z loops until port open → exits 0

→ main containers start simultaneously:
  app reads /vault/secrets/db-creds → loads env vars → entrypoint → app listens
  vault-agent sidecar runs own auth → watches for secret changes → re-renders on change

→ kubelet runs probes:
  liveness (process alive?) → fail = restart container
  readiness (ready to serve?) → fail = remove from endpoints

→ readiness passes → kubelet reports Ready → endpoint controller adds pod to Service
  → pod receives traffic via ClusterIP

StatefulSet variation:
  same flow but ordered creation (mariadb-0 Ready before mariadb-1 starts)
    → stable pod names + per-pod DNS → headless Service + ClusterIP Service
      → PVC per pod (survives deletion, data preserved) → rolling update in reverse order
