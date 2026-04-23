# TS-K8S-034 | 2026-04-16 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / CoreDNS / External DNS Resolution
Sub-techs: CoreDNS forward, FreeIPA DNS, WordPress external API calls,
           FluxCD GitRepository, HelmRepository, DNS fallback
Environment: DEV k8s cluster | lab.local domain | FreeIPA DNS at 10.0.60.10
Discovered during: IPA Domain Down DR Test (Part 1 & Part 2)
Related: TS-K8S-033 (Vault Agent DNS failure — internal DNS, same DR test),
         troubleshooting/linux/3-linux-nodes-dns-fallback.md (TS-LNX-003)
Re-opened: No

_____________________________________________________________________

[Issue Description]
During IPA outage, all external DNS resolution failed. This caused:

1. WordPress slowness — 4-12 second delays on every page load (external API timeouts)
2. FluxCD complete failure — can't reach github.com
3. Helm complete failure — can't fetch chart indexes

_____________________________________________________________________

[Analysis]

# Step 1: Browser DevTools — measured the delays

Homepage: ~4-5 second delay on initial document load.

Admin panel breakdown:
```
wp-admin/          200    20.2 kB    4.27 s    ← Initial page
admin-ajax.php     200    0.7 kB     12.16 s   ← 12 SECONDS
favicon.ico        302    0.5 kB     4.14 s    ← 4 SECONDS redirect
```

Static resources (CSS, JS, images) loaded instantly from memory/disk cache.
Only the server-side rendered requests were slow.

# Step 2: cURL from external client — confirmed server-side delay

```
sabry@Mohameds-Mac-mini ~ % time curl -I http://wordpress-dev.lab.local
HTTP/1.1 200 OK
Server: nginx/1.26.3
...
curl -I http://wordpress-dev.lab.local  0.01s user 0.01s system 0% cpu 4.909 total
```

Second request: 4.094 total. Client-side DNS was NOT the issue — my laptop
resolves `wordpress-dev.lab.local` via `/etc/hosts`, and external nginx forwards
to workers at `10.0.64.10-12:30080`. The delay was inside K8s.

# Step 3: DNS resolution from K8s node — confirmed IPA DNS down

```
[root@k8s-master1 k8s_admin]# nslookup gravatar.com
;; communications error to 10.0.60.10#53: connection refused
;; communications error to 10.0.60.10#53: connection refused
;; communications error to 10.0.60.10#53: connection refused
;; no servers could be reached

[root@k8s-master1 k8s_admin]# nslookup api.wordpress.org
;; communications error to 10.0.60.10#53: connection refused
;; no servers could be reached
```

IPA DNS down → no external DNS resolution → WordPress PHP waits for DNS timeout
on every external API call (Gravatar, api.wordpress.org), then continues.

# Step 4: FluxCD / Helm failures

CoreDNS external resolution failures:
```
dial tcp: lookup github.com on 10.96.0.10:53: server misbehaving
dial tcp: lookup grafana.github.io on 10.96.0.10:53: server misbehaving
dial tcp: lookup helm.releases.hashicorp.com on 10.96.0.10:53: server misbehaving
```

All HelmRepository resources failed — prometheus-community, grafana, hashicorp,
ingress-nginx, csi-driver-nfs. GitRepository/flux-system also failed (can't reach
github.com). No new deployments or updates possible, but existing workloads
continued running.

_____________________________________________________________________

[Final Root Cause]
DNS resolution chain:
```
WordPress Pod → CoreDNS (10.96.0.10) → FreeIPA (10.0.60.10) → External DNS
                                              ↓
                                         IPA DOWN
                                              ↓
                                     Connection Refused
```

CoreDNS forwards ALL queries to FreeIPA as the upstream resolver. When FreeIPA
is down, external domains (gravatar.com, api.wordpress.org, github.com) can't
resolve. WordPress makes synchronous external API calls during page rendering —
each DNS timeout adds ~5 seconds. `admin-ajax.php` makes multiple external calls,
totaling 12 seconds.

Why WordPress still works (just slow): MariaDB uses internal K8s DNS/IP, Vault
secrets are already cached, static resources are local. External calls timeout but
don't fail hard — WordPress waits then continues.

_____________________________________________________________________

[Final Solution]

# Step 1: Apply DNS fallback to all Linux nodes

Ran the DNS fallback playbook (adds 8.8.8.8 to zzz-ipa.conf on all nodes):
```
ansible-playbook playbooks/freeipa/dns_fallback.yml
```

See TS-LNX-003 for the full fallback implementation.

# Step 2: Restart CoreDNS to pick up new DNS config

CoreDNS caches the node's `/etc/resolv.conf` at startup. After applying the DNS
fix, had to restart CoreDNS to load the new fallback:

```
kubectl rollout restart deployment coredns -n kube-system
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

# Verification

Before fix:
```
wordpress-dev.lab.local    200    document    15.3 kB    4.19 s
admin-ajax.php             200    xhr         0.7 kB     12.16 s
```

After fix:
```
wordpress-dev.lab.local    200    document    13.9 kB    189 ms
```

4+ seconds → 189ms (22x faster).

Verified: Yes — WordPress loads instantly, FluxCD/Helm can reach external
domains via 8.8.8.8 fallback when FreeIPA is down.

_____________________________________________________________________

[Risk Level] MEDIUM

WordPress degraded but functional (slow, not broken). FluxCD/Helm completely
blocked — no new deployments possible during IPA outage. Existing workloads
unaffected.

_____________________________________________________________________

[References]
- TS-K8S-033 — Vault Agent DNS failure (internal DNS, same DR test)
- troubleshooting/linux/3-linux-nodes-dns-fallback.md — TS-LNX-003: DNS fallback implementation
- disaster-recovery/network-ipa-dns-outage.md — DR test: IPA down DNS cascade
