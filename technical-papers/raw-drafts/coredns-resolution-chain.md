CoreDNS Resolution Chain — Happy Path and FreeIPA Failure
==========================================================

Traces how a pod's DNS query travels through CoreDNS, which plugin
handles it, and where it ends up — for three query types (internal
service, static host, external). Then traces what breaks when
FreeIPA goes down, and how the hosts plugin fix prevents the cascade.


### How Pods Get Their DNS Config

    pod starts
      +-- kubelet writes /etc/resolv.conf inside the pod:
            nameserver 10.96.0.10
            search default.svc.cluster.local svc.cluster.local cluster.local

    10.96.0.10 = kube-dns Service ClusterIP (stable, never changes)
    every DNS query from every pod goes here first.


### The CoreDNS Plugin Chain

CoreDNS checks its Corefile plugins IN ORDER. first match wins,
no fallback to later plugins unless the matching plugin says
"fallthrough."

    [1] kubernetes plugin
          handles: *.cluster.local queries
          method: HTTP/gRPC → kube-apiserver → etcd lookup

    [2] hosts plugin
          handles: static entries (vault.lab.local, etc.)
          method: direct IP return from hardcoded list
          fallthrough: if query not in list → next plugin

    [3] forward plugin
          handles: everything else
          method: forwards to node's /etc/resolv.conf nameserver
          target: FreeIPA (10.0.60.10) → which forwards to 8.8.8.8


### The Components Involved

    coredns pods (x2 replicas, kube-system)
      +-- receives all pod DNS queries
      +-- talks to kube-apiserver for cluster.local
      +-- talks to FreeIPA for .lab.local and external (via forward)
      +-- serves static hosts entries directly

    kube-proxy (daemonset, 1 per node)
      +-- maintains iptables rules
      +-- forwards UDP :53 to CoreDNS pod IPs
          via kube-dns Service ClusterIP (10.96.0.10)

    kube-apiserver
      +-- receives queries from CoreDNS kubernetes plugin
      +-- reads from etcd → returns Service ClusterIP

    etcd
      +-- stores all Service records
      +-- source of truth for cluster.local resolution


========================================================
SCENARIO 1 — HAPPY PATH (FreeIPA Up)
========================================================


### Query Type 1 — Static Host (vault.lab.local)

vault-agent-init inside a pod needs to reach the Vault cluster.

    pod: DNS query for vault.lab.local
      |
      +-- UDP port 53 → kube-dns ClusterIP (10.96.0.10)
      |     +-- kube-proxy iptables → one of 2 CoreDNS pods
      |
      +-- CoreDNS plugin chain:
      |
      |     [1] kubernetes plugin
      |           is query cluster.local? → NO, skip
      |
      |     [2] hosts plugin
      |           is query vault.lab.local? → YES
      |           +-- returns 10.0.62.100 directly (static entry)
      |
      +-- DNS answer back to pod
      +-- vault-agent connects to 10.0.62.100:8200

    FreeIPA was never contacted. the hosts plugin short-circuits
    the entire chain for known infrastructure hostnames.


### Query Type 2 — Cluster Service (mariadb-svc.database.svc.cluster.local)

an app pod needs to reach MariaDB via its Service name.

    pod: DNS query for mariadb-svc.database.svc.cluster.local
      |
      +-- UDP port 53 → kube-dns ClusterIP (10.96.0.10)
      |     +-- kube-proxy iptables → CoreDNS pod
      |
      +-- CoreDNS plugin chain:
      |
      |     [1] kubernetes plugin
      |           is query cluster.local? → YES
      |           +-- HTTP/gRPC → kube-apiserver (port 6443)
      |           +-- kube-apiserver reads etcd
      |           +-- returns ClusterIP of mariadb-svc → 10.96.x.x
      |
      +-- DNS answer back to pod
      +-- pod connects to mariadb ClusterIP

    kubernetes plugin handled it. hosts and forward never checked.


### Query Type 3 — External (google.com)

a pod needs to reach an external domain.

    pod: DNS query for google.com
      |
      +-- UDP port 53 → kube-dns ClusterIP (10.96.0.10)
      |     +-- kube-proxy iptables → CoreDNS pod
      |
      +-- CoreDNS plugin chain:
      |
      |     [1] kubernetes plugin
      |           is query cluster.local? → NO, skip
      |
      |     [2] hosts plugin
      |           is query in static list? → NO, skip
      |           fallthrough → next plugin
      |
      |     [3] forward plugin
      |           forward . /etc/resolv.conf
      |           +-- reads NODE's /etc/resolv.conf (not pod's)
      |           +-- nameserver → FreeIPA (10.0.60.10)
      |           +-- FreeIPA checks its own forwarders
      |           +-- forwards to 8.8.8.8 (Google DNS)
      |           +-- answer returns up the chain
      |
      +-- DNS answer back to pod

    this is the ONLY query type that depends on FreeIPA being up.
    cluster.local is handled by kube-apiserver, static hosts are
    handled by the hosts plugin. only external and non-static
    .lab.local queries hit the forward plugin → FreeIPA.


========================================================
SCENARIO 2 — BAD PATH (FreeIPA Down)
========================================================


### Before the Fix — No Hosts Plugin

FreeIPA stops (ipactl stop, 10.0.60.10 unreachable).

    NEW pod starting — vault-agent-init needs vault.lab.local:
      |
      +-- UDP port 53 → CoreDNS pod
      |
      +-- CoreDNS plugin chain:
      |
      |     [1] kubernetes plugin
      |           is query cluster.local? → NO, skip
      |
      |     [2] hosts plugin
      |           NOT PRESENT YET → skip
      |
      |     [3] forward plugin
      |           +-- reads node /etc/resolv.conf → FreeIPA (10.0.60.10)
      |           +-- FreeIPA DOWN
      |           +-- timeout → "server misbehaving"
      |           +-- CoreDNS returns error to pod
      |
      +-- vault-agent-init retries with exponential backoff:
            retry 1  → 250ms
            retry 2  → 500ms
            retry 3  → 1s
            ...
            retry 12 → 1m
            +-- exitCode=1
            +-- pod stuck in Init:1/2 forever

    EXISTING pods (vault-agent sidecar already running):
      |
      +-- already have vault token + secrets in memory
      +-- keep running (until token TTL expires ~10min)
      |
      +-- token renewal needs vault.lab.local → DNS fails
      +-- vault-agent crashes exitCode=1
      |
      +-- app container keeps running (cached secrets)
      +-- but secrets stop refreshing
      |
      +-- result: app works with stale secrets until restart,
          new pods can't start at all

    the cascade: FreeIPA down → DNS broken → vault-agent can't
    resolve → init container fails → no new pods → existing pods
    degrade as token TTL expires.

    cluster.local queries (service-to-service) still work fine —
    kubernetes plugin handles those without touching FreeIPA.


### After the Fix — Hosts Plugin Added

same scenario: FreeIPA stops.

    NEW pod starting — vault-agent-init needs vault.lab.local:
      |
      +-- UDP port 53 → CoreDNS pod
      |
      +-- CoreDNS plugin chain:
      |
      |     [1] kubernetes plugin
      |           is query cluster.local? → NO, skip
      |
      |     [2] hosts plugin (NOW PRESENT)
      |           is query vault.lab.local? → YES
      |           +-- returns 10.0.62.100 directly
      |           +-- never reaches forward plugin
      |           +-- FreeIPA never contacted
      |
      +-- vault-agent-init authenticates to Vault
      +-- pod starts normally

    the hosts plugin breaks the dependency chain. DNS for critical
    infrastructure hostnames (vault VIP, FreeIPA itself, etc.) is
    resolved from static entries before the forward plugin is ever
    reached. FreeIPA can be completely down and new pods still start.

    what still breaks when IPA is down:
      +-- external DNS (google.com) → forward plugin → timeout
      +-- any .lab.local hostname NOT in the hosts list
      +-- new Kerberos authentication (no KDC)
      +-- SSSD user lookups on nodes (but cached data survives)

    what keeps working:
      +-- cluster.local service resolution (kubernetes plugin)
      +-- static host resolution (hosts plugin)
      +-- existing pod-to-pod traffic (already resolved)
      +-- existing Kerberos tickets (until TGT expires)
