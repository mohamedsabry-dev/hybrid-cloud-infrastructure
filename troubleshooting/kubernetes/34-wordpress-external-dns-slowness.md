# TS-K8S-034 | 2026-04-16 | RESOLVED

## 1. Context
- System: CoreDNS / External DNS Resolution
- Environment: DEV (lab.local)
- Related components: WordPress pods, FluxCD, Helm, CoreDNS, FreeIPA DNS, External APIs
- Discovery: **Discovered during IPA Domain Down DR Test (Part 1 & Part 2)**

---

## 2. Issue

During IPA outage, all external DNS resolution fails. This causes:
1. **WordPress slowness** - 4-12 second delays (external API timeouts)
2. **FluxCD complete failure** - Cannot reach github.com
3. **Helm complete failure** - Cannot fetch chart indexes

### Observed Behavior
- WordPress homepage: ~4-5 second delay
- WordPress admin panel: 4.27 second initial load
- admin-ajax.php: 12.16 second response time
- favicon.ico redirect: 4.14 second delay

### Expected Behavior
- WordPress pages should load in <1 second under normal conditions
- Admin panel should be responsive

---

## 3. Evidence

### 3.1 Browser DevTools Analysis (Initial Observation)

**First Observation - Homepage:**
```
wordpress-dev.lab.local	200	document	Other	15.3 kB	4.19 s
dashicons.min.css?ver=6.9.4	200	stylesheet	(index):14	(memory cache)	0 ms
admin-bar.min.css?ver=6.9.4	200	stylesheet	(index):15	(memory cache)	0 ms
index.min.js?ver=66c613f68580994bb00a	200	script	(index):159	(memory cache)	0 ms
ImagefYWQfzzc_400x400.jpg	200	jpeg	(index):265	(memory cache)	0 ms
view.min.js?ver=b0f909c3ec791c383210	200	script	(index):331	(memory cache)	0 ms
hoverintent-js.min.js?ver=2.2.1	200	script	(index):854	(memory cache)	0 ms
admin-bar.min.js?ver=6.9.4	200	script	(index):855	(memory cache)	0 ms
Imagedd10eaca49214cba39083e9011942451bd2e479eae2b5fc5c69d47e905e4ebd4?s=52&d=mm&r=g	304	jpeg	(index):169	0.4 kB	153 ms
Imagedd10eaca49214cba39083e9011942451bd2e479eae2b5fc5c69d47e905e4ebd4?s=128&d=mm&r=g	304	jpeg	(index):169	0.4 kB	153 ms
9240272-hd_1080_1920_30fps-1.mp4	206	media	(index):387	(disk cache)	267 ms
wp-emoji-release.min.js?ver=6.9.4	200	script	wp-emoji-loader.min.js:3	(memory cache)	0 ms
data:application/x-…	200	font	/wp-admin/load-styles.php?...	(memory cache)	0 ms
Manrope-VariableFont_wght.woff2	200	font	(index):387	(memory cache)	0 ms
favicon.ico	302	text/html / Redirect	Other	0.5 kB	4.06 s
Otherw-logo-blue-white-bg.png	200	png	favicon.ico	(disk cache)	1 ms
```

**Key observation:** Delay 5 second as per developer logs, favicon is just the WordPress small icon.

**Admin Panel Analysis:**
```
wp-admin/	200	document	Other	20.2 kB	4.27 s
load-scripts.php?...jquery-core...	200	script	wp-admin/:242	(memory cache)	0 ms
i18n.min.js?ver=c26c3dc7bed366793375	200	script	wp-admin/:65	(memory cache)	0 ms
a11y.min.js?ver=cb460b4676c94bd228ed	200	script	wp-admin/:82	(memory cache)	0 ms
common.min.js?ver=6.9.4	200	script	wp-admin/:853	(memory cache)	0 ms
...
thickbox.css?ver=6.9.4	200	stylesheet	wp-admin/:22	(disk cache)	2 ms
editor.min.css?ver=6.9.4	200	stylesheet	wp-admin/:619	(disk cache)	3 ms
Imagedd10eaca49214cba39083e9011942451bd2e479eae2b5fc5c69d47e905e4ebd4?s=52&d=mm&r=g	304	jpeg	wp-admin/:317	0.4 kB	149 ms
Imagedd10eaca49214cba39083e9011942451bd2e479eae2b5fc5c69d47e905e4ebd4?s=128&d=mm&r=g	304	jpeg	wp-admin/:317	0.4 kB	148 ms
Imagedd10eaca49214cba39083e9011942451bd2e479eae2b5fc5c69d47e905e4ebd4?s=100&d=mm&r=g	304	jpeg	wp-admin/:564	0.4 kB	148 ms
Image8e1606e6fba450a9362af43874c1b2dfad34c782e33d0a51e1b46c18a2a567dd?s=100&d=mm&r=g	304	png	wp-admin/:590	0.4 kB	149 ms
data:application/x-…	200	font	...	(memory cache)	0 ms
Manrope-VariableFont_wght.woff2	200	font	wp-admin/:869	(memory cache)	0 ms
ImageloadingAnimation.gif	200	gif	thickbox.js?ver=3.1-20121105:18	(memory cache)	0 ms
admin-ajax.php	200	xhr	load-scripts.php?...	0.7 kB	12.16 s    ← 12 SECONDS!
favicon.ico	302	text/html / Redirect	Other	0.5 kB	4.14 s    ← 4 SECONDS redirect
Otherw-logo-blue-white-bg.png	200	png	favicon.ico	(disk cache)	1 ms
Imagespinner-2x.gif	200	gif	load-styles.php?...	(disk cache)
```

### 3.2 Slowest Requests Summary
```
┌───────────────┬────────┬─────────┬───────────┐
│    Request    │ Status │  Size   │   Time    │
├───────────────┼────────┼─────────┼───────────┤
│ admin-ajax.php│ 200    │ 0.7 kB  │ 12.16 s   │ ← 12 SECONDS!
├───────────────┼────────┼─────────┼───────────┤
│ favicon.ico   │ 302    │ 0.5 kB  │ 4.14 s    │ ← 4 SECONDS redirect
├───────────────┼────────┼─────────┼───────────┤
│ wp-admin/     │ 200    │ 20.2 kB │ 4.27 s    │ ← Initial page
└───────────────┴────────┴─────────┴───────────┘
```

### 3.3 cURL Test from External Client
```bash
sabry@Mohameds-Mac-mini ~ % time curl -I http://wordpress-dev.lab.local
HTTP/1.1 200 OK
Server: nginx/1.26.3
Date: Wed, 15 Apr 2026 20:04:44 GMT
Content-Type: text/html; charset=UTF-8
Connection: keep-alive
Set-Cookie: wordpress-sticky=1776283480.908.22.767968|f2bd2b074a2457a1ef9b065ade9d78ef; Expires=Fri, 17-Apr-26 20:04:39 GMT; Max-Age=172800; Path=/; HttpOnly
X-Powered-By: PHP/8.2.30
Link: <http://wordpress-dev.lab.local/wp-json/>; rel="https://api.w.org/"

curl -I http://wordpress-dev.lab.local  0.01s user 0.01s system 0% cpu 4.909 total

sabry@Mohameds-Mac-mini ~ % time curl -I http://wordpress-dev.lab.local
HTTP/1.1 200 OK
...
curl -I http://wordpress-dev.lab.local  0.01s user 0.01s system 0% cpu 4.094 total
```

### 3.4 Initial Investigation Notes

**Client-side DNS is NOT the issue:**
```
- Connection from laptop resolves http://wordpress-dev.lab.local/ via /etc/hosts
- No dependency on IPA for client DNS resolution
- External nginx configured to forward to workers as 10.0.64.10-12

upstream k8s_workers {
    least_conn;
    server 10.0.64.10:30080;
    server 10.0.64.11:30080;
    server 10.0.64.12:30080;
}
```

**Conclusion:** Delay expected to be internally in K8s, not external client DNS.

### 3.5 DNS Resolution Test from K8s Node

```bash
[root@k8s-master1 k8s_admin]# nslookup gravatar.com
;; communications error to 10.0.60.10#53: connection refused
;; communications error to 10.0.60.10#53: connection refused
;; communications error to 10.0.60.10#53: connection refused
;; no servers could be reached

[root@k8s-master1 k8s_admin]# nslookup api.wordpress.org
;; communications error to 10.0.60.10#53: connection refused
;; communications error to 10.0.60.10#53: connection refused
;; communications error to 10.0.60.10#53: connection refused
;; no servers could be reached
```

**Confirmed:** IPA DNS is down → No external DNS resolution → WordPress timeouts.

### 3.6 FluxCD/Helm Failures (Part 1 Evidence)

**CoreDNS External Resolution Failures:**
```
dial tcp: lookup github.com on 10.96.0.10:53: server misbehaving
dial tcp: lookup grafana.github.io on 10.96.0.10:53: server misbehaving
dial tcp: lookup helm.releases.hashicorp.com on 10.96.0.10:53: server misbehaving
```

**All HelmRepository Resources Failed:**
```
┌─────────────────────────┬────────────────────────────────────┬─────────┐
│      HelmRepository     │          External Domain           │ Status  │
├─────────────────────────┼────────────────────────────────────┼─────────┤
│ prometheus-stack        │ prometheus-community.github.io     │ FAILED  │
├─────────────────────────┼────────────────────────────────────┼─────────┤
│ grafana                 │ grafana.github.io                  │ FAILED  │
├─────────────────────────┼────────────────────────────────────┼─────────┤
│ hashicorp               │ helm.releases.hashicorp.com        │ FAILED  │
├─────────────────────────┼────────────────────────────────────┼─────────┤
│ ingress-nginx           │ kubernetes.github.io               │ FAILED  │
├─────────────────────────┼────────────────────────────────────┼─────────┤
│ csi-driver-nfs          │ raw.githubusercontent.com          │ FAILED  │
└─────────────────────────┴────────────────────────────────────┴─────────┘
```

**GitRepository Failed:**
```
GitRepository/flux-system - FAILED (cannot reach github.com)
```

**Impact:**
- FluxCD cannot pull manifests from GitHub
- Helm cannot fetch chart indexes
- No new deployments or updates possible
- Existing workloads continue running (already deployed)

---

## 4. Root Cause Analysis

### 4.1 DNS Resolution Chain
```
WordPress Pod → CoreDNS (10.96.0.10) → FreeIPA (10.0.60.10) → External DNS
                                              ↓
                                         IPA DOWN
                                              ↓
                                     Connection Refused
```

### 4.2 Affected External Services
```
┌─────────────────────────────────────┬──────────────────────┬────────────────────────┬─────────────┐
│              Service                │       Purpose        │      DNS Required      │   Impact    │
├─────────────────────────────────────┼──────────────────────┼────────────────────────┼─────────────┤
│ Gravatar (gravatar.com)             │ User avatars         │ ✅ Yes                 │ WP Slow     │
├─────────────────────────────────────┼──────────────────────┼────────────────────────┼─────────────┤
│ api.wordpress.org                   │ Plugin/update checks │ ✅ Yes                 │ WP Slow     │
├─────────────────────────────────────┼──────────────────────┼────────────────────────┼─────────────┤
│ github.com                          │ FluxCD GitRepository │ ✅ Yes                 │ Flux FAIL   │
├─────────────────────────────────────┼──────────────────────┼────────────────────────┼─────────────┤
│ grafana.github.io                   │ Grafana Helm charts  │ ✅ Yes                 │ Helm FAIL   │
├─────────────────────────────────────┼──────────────────────┼────────────────────────┼─────────────┤
│ prometheus-community.github.io      │ Prometheus charts    │ ✅ Yes                 │ Helm FAIL   │
├─────────────────────────────────────┼──────────────────────┼────────────────────────┼─────────────┤
│ helm.releases.hashicorp.com         │ HashiCorp charts     │ ✅ Yes                 │ Helm FAIL   │
├─────────────────────────────────────┼──────────────────────┼────────────────────────┼─────────────┤
│ kubernetes.github.io                │ Ingress-nginx charts │ ✅ Yes                 │ Helm FAIL   │
└─────────────────────────────────────┴──────────────────────┴────────────────────────┴─────────────┘
```

### 4.3 Delay Calculation
```
┌───────────────────┬────────────────────────────┬───────────┐
│      Request      │        What Happens        │  Result   │
├───────────────────┼────────────────────────────┼───────────┤
│ gravatar.com      │ DNS timeout                │ +5s delay │
├───────────────────┼────────────────────────────┼───────────┤
│ api.wordpress.org │ DNS timeout                │ +5s delay │
├───────────────────┼────────────────────────────┼───────────┤
│ admin-ajax.php    │ Multiple DNS calls timeout │ 12s total │
└───────────────────┴────────────────────────────┴───────────┘
```

### 4.4 Why WordPress Still Works (Just Slow)

1. **Internal services work** - MariaDB connection uses internal K8s DNS/IP
2. **Cached credentials** - Vault Agent already injected secrets before IPA down
3. **Local resources** - CSS, JS, images served from local storage (memory cache)
4. **External calls timeout but don't fail hard** - WordPress waits for timeout then continues

---

## 5. Impact Assessment

### What Works
- WordPress core functionality (login, post viewing)
- Database operations (internal K8s DNS)
- Local static resources
- **Existing deployments** - Already running pods continue to work
- K8s cluster operations (uses internal IPs)

### What Doesn't Work
| Component | Impact | Severity |
|-----------|--------|----------|
| FluxCD | Cannot pull from GitHub | **CRITICAL** - No deployments |
| Helm | Cannot fetch chart indexes | **CRITICAL** - No chart updates |
| WordPress external APIs | 5-12 second timeouts | MODERATE - Still works |
| Gravatar images | Timeout then fallback | LOW - Cosmetic |

### What Is Slow
- WordPress page loads: 4-12 second delays
- admin-ajax.php calls: 12+ seconds
- Any pod making external HTTP calls

### User Experience
- WordPress: Pages eventually load after 4-12 second delays
- FluxCD/Helm: **Complete failure** - No new deployments possible
- Admin operations: Frustrating but functional

---

## 6. Hypotheses

### Hypothesis 1: CoreDNS Forward Configuration
- CoreDNS forwards all queries to IPA first
- No fallback DNS configured for external domains
- Each external query times out before failing

### Hypothesis 2: WordPress External API Calls
- WordPress makes synchronous external API calls on page load
- No graceful degradation when DNS fails
- Multiple external calls = cumulative timeout

### Hypothesis 3: PHP DNS Resolution Behavior
- PHP's DNS resolution may try multiple times
- Each retry adds to total delay
- Default timeout settings not optimized for degraded mode

---

## 7. Potential Solutions (Not Implemented)

### Option A: Add Fallback DNS to CoreDNS
Add Google DNS (8.8.8.8) as fallback for external domains in CoreDNS config.

### Option B: Disable External Features in WordPress
- Disable Gravatar in WordPress settings
- Disable update checks temporarily
- Configure WP_HTTP_BLOCK_EXTERNAL

### Option C: DNS Caching Layer
- Add caching resolver (dnsmasq, unbound)
- Cache external DNS responses
- Survive short DNS outages

---

## 8. Related Documentation

| File | Description |
|------|-------------|
| `troubleshooting/kubernetes/33-vault-agent-dns-failure-new-pod-blocking.md` | TS-K8S-033: Vault Agent DNS dependency (internal DNS) |
| `disaster-recovery/tmp-ipa-domain-down-part1.md` | Part 1 DR test - Flux/Helm failures first discovered |
| `disaster-recovery/tmp-ipa-domain-down-part2.md` | Part 2 DR test - WordPress slowness investigation |

---

## 9. Solution

### Step 1: Apply DNS Fallback to All Linux Nodes

Run the DNS fallback playbook (adds 8.8.8.8 to zzz-ipa.conf on all nodes):

```bash
ansible-playbook playbooks/freeipa/dns_fallback.yml
```

See: `troubleshooting/linux/3-linux-nodes-dns-fallback.md` (TS-LNX-003)

### Step 2: Restart CoreDNS to Pick Up New DNS Config

CoreDNS caches the node's `/etc/resolv.conf` at startup. After applying the DNS fix,
restart CoreDNS to load the new fallback DNS:

```bash
kubectl rollout restart deployment coredns -n kube-system
```

Verify pods restarted:

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

---

## 10. Fix Evidence

### Before Fix
```
wordpress-dev.lab.local    200    document    15.3 kB    4.19 s
admin-ajax.php             200    xhr         0.7 kB     12.16 s
```

### After Fix
```
wordpress-dev.lab.local    200    document    13.9 kB    189 ms
```

**Result:** 4+ seconds → 189ms (22x faster)

---

## 11. Status

**RESOLVED**
