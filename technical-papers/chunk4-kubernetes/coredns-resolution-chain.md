CoreDNS Resolution Chain — Happy Path and FreeIPA Failure (Summary Trace)
==========================================================================

pre-trace:
  kubelet writes /etc/resolv.conf into every pod → nameserver 10.96.0.10 (kube-dns ClusterIP)
    → kube-proxy iptables forward UDP :53 → one of 2 CoreDNS pods
  CoreDNS plugin order: [1] kubernetes (cluster.local) → [2] hosts (static entries, fallthrough) → [3] forward (→ FreeIPA → 8.8.8.8)

--- happy path ---

static host (vault.lab.local):
  pod → UDP :53 → kube-dns ClusterIP → kube-proxy iptables → CoreDNS pod
    → kubernetes plugin: cluster.local? NO, skip
      → hosts plugin: vault.lab.local? YES → returns 10.0.62.100 directly
        → DNS answer back to pod → vault-agent connects to 10.0.62.100:8200
          (FreeIPA never contacted)

cluster service (mariadb-svc.database.svc.cluster.local):
  pod → UDP :53 → kube-dns ClusterIP → kube-proxy iptables → CoreDNS pod
    → kubernetes plugin: cluster.local? YES
      → HTTP/gRPC → kube-apiserver → etcd → returns ClusterIP 10.96.x.x
        → DNS answer back to pod → pod connects to mariadb ClusterIP
          (hosts and forward never checked)

external (google.com):
  pod → UDP :53 → kube-dns ClusterIP → kube-proxy iptables → CoreDNS pod
    → kubernetes plugin: cluster.local? NO, skip
      → hosts plugin: in static list? NO, fallthrough
        → forward plugin → node /etc/resolv.conf → FreeIPA (10.0.60.10)
          → FreeIPA forwards to 8.8.8.8 → answer returns up the chain
            (ONLY query type that depends on FreeIPA)

--- bad path (FreeIPA down, before hosts plugin fix) ---

new pod needs vault.lab.local:
  pod → UDP :53 → CoreDNS pod
    → kubernetes: skip → hosts: NOT PRESENT → forward → FreeIPA (10.0.60.10) DOWN
      → timeout → "server misbehaving" → CoreDNS returns error
        → vault-agent-init retries with exponential backoff (250ms → 1m)
          → exitCode=1 → pod stuck in Init:1/2 forever

existing pods (vault-agent sidecar running):
  token + secrets in memory → keep running until TTL expires (~10min)
    → token renewal needs vault.lab.local → DNS fails → vault-agent crashes
      → app container keeps running with stale secrets → stops refreshing

cascade: FreeIPA down → DNS broken → vault-agent can't resolve
  → init fails → no new pods → existing pods degrade as token TTL expires

--- bad path (FreeIPA down, after hosts plugin fix) ---

new pod needs vault.lab.local:
  pod → UDP :53 → CoreDNS pod
    → kubernetes: skip → hosts plugin (NOW PRESENT): vault.lab.local? YES
      → returns 10.0.62.100 directly → never reaches forward → FreeIPA never contacted
        → vault-agent authenticates → pod starts normally

still breaks: external DNS, unlisted .lab.local, new Kerberos auth, SSSD lookups
still works: cluster.local, static hosts, existing pod-to-pod, existing Kerberos tickets
