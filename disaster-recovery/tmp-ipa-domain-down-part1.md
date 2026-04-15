# IPA Domain Down - Part 1
# Date: 2026-04-15
# Result: COMPLETED (See Part 2 for continued testing)

---

## Scope

Stop FreeIPA server. Test DNS/auth dependencies.

---

## Environment

| Component | Details |
|-----------|---------|
| FreeIPA Server | freeipa.lab.local |
| K8s Masters | k8s-master1/2/3.lab.local (10.0.61.10-12) |
| K8s Workers | k8s-worker1/2/3.lab.local (10.0.64.10-12) |
| Vault Cluster | vault1.lab.local (10.0.62.10) - Active |
| K8s Version | v1.35.3 |
| Vault Version | 1.21.4 |

---

## Baseline Status (Pre-Test)

### FreeIPA Services
```
Directory Service: RUNNING
krb5kdc Service: RUNNING
kadmin Service: RUNNING
named Service: RUNNING
httpd Service: RUNNING
ipa-custodia Service: RUNNING
pki-tomcatd Service: RUNNING
ipa-otpd Service: RUNNING
ipa-dnskeysyncd Service: RUNNING
```

### K8s Cluster
```
NAME                    STATUS   ROLES           INTERNAL-IP
k8s-master1.lab.local   Ready    control-plane   10.0.61.10
k8s-master2.lab.local   Ready    control-plane   10.0.61.11
k8s-master3.lab.local   Ready    control-plane   10.0.61.12
k8s-worker1.lab.local   Ready    <none>          10.0.64.10
k8s-worker2.lab.local   Ready    <none>          10.0.64.11
k8s-worker3.lab.local   Ready    <none>          10.0.64.12
```

### Vault Status
```
Initialized: true
Sealed: false
HA Mode: active
Seal Type: awskms
Storage Type: raft
```

---

## Pre-Flight Checks

### Resolution Method

#### /etc/hosts (k8s-master1)
```
127.0.0.1 k8s-master1.lab.local k8s-master1
127.0.0.1 localhost.localdomain localhost
# NOTE: No other node IPs present - relies on DNS!
# Managed by cloud-init: /etc/cloud/templates/hosts.redhat.tmpl
```

#### /etc/resolv.conf (k8s-master1)
```
search lab.local
nameserver 10.0.60.10   # <-- FreeIPA DNS server
```

#### kubelet.conf API server
```
server: https://10.0.61.10:6443   # <-- Uses IP, not hostname (GOOD)
```

### Risk Assessment
| Component | Uses DNS? | Risk if IPA Down |
|-----------|-----------|------------------|
| kubelet → API server | No (IP) | LOW |
| Node name resolution | Yes | HIGH |
| SSH by hostname | Yes | HIGH |
| New connections | Yes | HIGH |

---

## Mitigation: /etc/hosts Fallback

### Playbook
**File:** `ansible/dev/playbooks/k8s/k8s_hosts_fallback.yml`

Adds static host entries to all K8s nodes so they can resolve each other (and Vault) without DNS.

```yaml
# Entries added to /etc/hosts on all K8s nodes:
# K8S Nodes Masters
10.0.61.10  k8s-master1.lab.local k8s-master1
10.0.61.11  k8s-master2.lab.local k8s-master2
10.0.61.12  k8s-master3.lab.local k8s-master3
# K8S Nodes Workers
10.0.64.10  k8s-worker1.lab.local k8s-worker1
10.0.64.11  k8s-worker2.lab.local k8s-worker2
10.0.64.12  k8s-worker3.lab.local k8s-worker3
# K8S VIP
10.0.61.100 k8s-api.lab.local k8s-api
# Vault-Cluster
10.0.62.10  vault1.lab.local  vault1
10.0.62.11  vault2.lab.local  vault2
10.0.62.12  vault3.lab.local  vault3
10.0.62.100 vault.lab.local   vault
```

### Execution (Pre-Test)
```bash
# Run from Ansible node
cd /srv/repo/ansible/dev/
ansible-playbook -i inventory/inventory.ini playbooks/k8s/k8s_hosts_fallback.yml
```
**Result:** PENDING

### Future Deployments
This playbook is included in the K8s setup workflow:
**File:** `.github/workflows/dev-k8s-full-setup.yml` (line 241)

```yaml
ansible-playbook -i inventory/inventory.ini playbooks/k8s/k8s_hosts_fallback.yml
```

Runs automatically after `flux_setup.yml` in Job 3 (Setup K8s Cluster).

---

## Test Execution

### Phase 0: Apply /etc/hosts Fallback
```bash
cd /srv/repo/ansible/dev/
ansible-playbook -i inventory/inventory.ini playbooks/k8s/k8s_hosts_fallback.yml
```
**Result:** ✅ APPLIED (all 6 nodes: k8s-master1/2/3, k8s-worker1/2/3)

### Phase 1: Stop IPA
```bash
ssh root@freeipa 'ipactl stop'
```
**Result:** ✅ STOPPED

**Note:** SSH to FreeIPA still works because Ansible node has `/etc/hosts` entry:
```
10.0.60.10 freeipa.lab.local freeipa
```
SSH resolves via `/etc/hosts` before DNS - can still manage IPA when DNS is down.

### Phase 2: Service Checks (IPA Down)

| Service | Command | Expected | Actual |
|---------|---------|----------|--------|
| K8s API | `kubectl get nodes` | UP | ✅ UP (all 6 nodes Ready) |
| SSH to worker (by IP) | `ssh root@10.0.64.10 'hostname'` | UP | ✅ UP |
| SSH to worker (by hostname) | `ssh root@k8s-worker1.lab.local` | UP | ❌ FAIL (from Ansible) |
| Vault (by IP) | `ssh root@10.0.62.10 'vault status'` | UP | ✅ UP (unsealed) |
| Vault (by hostname) | `ssh root@vault1.lab.local 'vault status'` | UP | ❌ FAIL |
| DNS resolution | `nslookup k8s-master1.lab.local` | FAIL | ❌ FAIL (as expected) |

### Key Observations

**K8s Cluster (IPA Down):**
```
NAME                    STATUS   ROLES           INTERNAL-IP
k8s-master1.lab.local   Ready    control-plane   10.0.61.10
k8s-master2.lab.local   Ready    control-plane   10.0.61.11
k8s-master3.lab.local   Ready    control-plane   10.0.61.12
k8s-worker1.lab.local   Ready    <none>          10.0.64.10
k8s-worker2.lab.local   Ready    <none>          10.0.64.11
k8s-worker3.lab.local   Ready    <none>          10.0.64.12
```
**Verdict:** K8s cluster fully operational with `/etc/hosts` fallback.

**Vault Cluster (IPA Down):**
```
Sealed: false
HA Mode: active
```
**Verdict:** Vault operational, accessible by IP.

**Ansible Node Gap:**
- Ansible node only has FreeIPA in `/etc/hosts`, not other nodes
- Must use IPs to reach K8s/Vault nodes when DNS down
- SSH still works via trusted keys (injected by Terraform/AWS Secrets)

### Phase 3: Restore IPA
```bash
ssh root@freeipa 'ipactl start'
```
**Result:** PENDING

---

## Findings

### Dependencies Identified

| Question | Answer | Source |
|----------|--------|--------|
| K8s uses IPs or DNS? | **DNS** (FreeIPA) | `/etc/resolv.conf` → `10.0.60.10` |
| /etc/hosts has node IPs? | **NO** - only localhost | cloud-init managed |
| kubelet → API server | **IP** (10.0.61.10:6443) | `/etc/kubernetes/kubelet.conf` |
| K8s control-plane-endpoint | **IP** (10.0.61.100:16443) | `k8s_init.yml` line 12 |
| Ansible inventory | **FQDNs** (IPs commented out) | `inventory.ini` |

### Root Cause: Intentional Design

**File:** `ansible/dev/inventory/inventory.ini` (lines 6-9)
```ini
# WHY FQDN HOSTNAMES:
#   - FreeIPA provides DNS resolution for .lab.local domain
#   - Kerberos/GSSAPI authentication requires hostnames (not IPs)
#   - Service principals are tied to hostname@REALM
```

### Architecture Implications

| Component | Depends on IPA DNS | Impact if IPA Down |
|-----------|-------------------|-------------------|
| K8s internal (kubelet↔API) | No (uses IPs) | None |
| K8s node registration | Yes (hostnames) | New joins fail |
| SSH by hostname | Yes | Fails |
| SSH by IP | No | Works |
| Ansible playbooks | Yes (FQDNs in inventory) | Fails |
| Kerberos auth | Yes | Fails |
| New cert issuance | Yes | Fails |

### Vault ↔ K8s Integration

**File:** `ansible/dev/playbooks/k8s/integration-vault-k8s-trust.yml`

| Direction | Endpoint | Uses DNS? |
|-----------|----------|-----------|
| Vault → K8s API (token validation) | `https://10.0.61.100:16443` | **No (IP)** |
| K8s Pods → Vault | Depends on app config | Check VAULT_ADDR |

Vault's K8s auth callback uses the VIP IP - safe from DNS outage.

### Issues Discovered

**1. Ansible Node Missing /etc/hosts Entries**
- Ansible node only has `freeipa.lab.local` in `/etc/hosts`
- Cannot resolve `vault1.lab.local`, `k8s-worker1.lab.local`, etc. when IPA DNS down
- **Workaround:** Use IPs directly
- **Fix:** Add all managed hosts to Ansible node's `/etc/hosts`

**2. CoreDNS Cannot Resolve External Domains (Critical)**
**TS Case:** `troubleshooting/kubernetes/34-wordpress-external-dns-slowness.md` (TS-K8S-034)

When IPA DNS down, CoreDNS fails to resolve external hostnames:
```
dial tcp: lookup github.com on 10.96.0.10:53: server misbehaving
dial tcp: lookup grafana.github.io on 10.96.0.10:53: server misbehaving
dial tcp: lookup helm.releases.hashicorp.com on 10.96.0.10:53: server misbehaving
```

**Impact:**
- FluxCD cannot pull from GitHub
- Helm cannot fetch chart indexes
- Any pod needing external DNS fails

**Root Cause:** CoreDNS forwards to FreeIPA (10.0.60.10), no fallback upstream.

**3. Node /etc/resolv.conf - No Fallback DNS**
**TS Case:** `troubleshooting/linux/10-linux-nodes-dns-fallback.md` (TS-LNX-010)

```
nameserver 10.0.60.10   # Only FreeIPA, no public DNS fallback
```
**Fix:** Add fallback DNS in Terraform VM provisioning or cloud-init.

**4. Vault Agent Sidecar Crashed (Root Cause Found)**
**TS Case:** `troubleshooting/kubernetes/33-vault-agent-dns-failure-new-pod-blocking.md` (TS-K8S-033)

**Error Log:**
```
vault.read(secret/data/wordpress/config): Get "https://vault.lab.local:8200/...":
dial tcp: lookup vault.lab.local on 10.96.0.10:53: server misbehaving (exceeded maximum retries)
```

**Timeline:**
| Time | Event |
|------|-------|
| 18:29:10 | Last successful token renewal |
| 18:36:12 | First DNS failure (IPA went down) |
| 18:36:12 → 18:46:08 | 12 retries with exponential backoff (250ms → 1min) |
| 18:46:08 | Exceeded max retries, Exit Code 1 |

**Root Cause:** Vault Agent uses `vault.lab.local` hostname. CoreDNS forwards to FreeIPA DNS (down). No fallback.

**Impact:** All pods with Vault Agent sidecars crash after ~10min of DNS failure.

**5. Flux/Helm Repository Failures**
**TS Case:** `troubleshooting/kubernetes/34-wordpress-external-dns-slowness.md` (TS-K8S-034) - Same root cause as #2

All HelmRepository resources failing:
- `prometheus-stack` - FAILED
- `grafana` - FAILED
- `hashicorp` - FAILED
- `ingress-nginx` - FAILED
- `csi-driver-nfs` - FAILED
- `GitRepository/flux-system` - FAILED (cannot reach github.com)

**6. Ansible Slow Execution When Using IP Fallback - RESOLVED**

**Status:** ✅ RESOLVED during Part 2 testing
**TS Case:** `troubleshooting/identity/9-ansible-sssd-knownhosts-timeout.md`

When IPA DNS is down:
- Ansible ad-hoc commands take **~28-34 seconds** to execute on a single node
- Normal execution: < 5 seconds
- `raw` module: ~0.7 seconds (fast - single SSH, no Python)

**Root Cause Identified:**
SSH `KnownHostsCommand` (`/usr/bin/sss_ssh_knownhosts`) attempts to fetch host keys from SSSD/FreeIPA. When IPA is down, each lookup times out. Ansible makes 7-8 SSH connections per module execution, with 2 SSSD lookups each = ~28-34 seconds total delay.

**NOT the root cause (eliminated during investigation):**
- ❌ Kerberos/GSSAPI authentication
- ❌ Python interpreter discovery
- ❌ SSH UseDNS setting
- ❌ Python socket.getfqdn() calls

**Solution Applied:**
Add to Ansible inventory (`first_setup_inventory.ini`):
```ini
[all:vars]
ansible_ssh_common_args='-o KnownHostsCommand=none'
```

**Result:** Execution time reduced from **28 seconds → 3 seconds**

---

**7. Node vs Pod DNS Resolution (Critical Understanding)**

| Level | DNS Source | /etc/hosts Fallback? |
|-------|------------|---------------------|
| **Node** (SSH, ping) | `/etc/hosts` → DNS | ✅ Works |
| **Pod** (containers) | CoreDNS (10.96.0.10) | ❌ Ignored |

**Test Evidence:**
```bash
# From k8s-master1 NODE - works via /etc/hosts
[root@k8s-master1]# ping vault.lab.local
PING vault.lab.local (10.0.62.100) 56(84) bytes of data.
64 bytes from vault.lab.local: icmp_seq=1 ttl=63 time=2.94 ms

# From POD (vault-agent) - fails via CoreDNS
dial tcp: lookup vault.lab.local on 10.96.0.10:53: server misbehaving
```

**Conclusion:** The `/etc/hosts` fallback playbook protects **node-level** operations (SSH, kubelet, etc.) but does NOT protect **pod-level** DNS resolution. Pods use CoreDNS which forwards to FreeIPA DNS.

---

## Recovery Procedure

```bash
# Start IPA services
ssh root@freeipa 'ipactl start'

# Verify all services running
ssh root@freeipa 'ipactl status'

# Verify DNS resolution restored
nslookup k8s-master1.lab.local
```

---

## Pending Investigation

### WordPress Slowness (~10s delay when IPA down)

**Symptoms:**
- WordPress site opens but with ~10 second average delay when IPA DNS is down
- Site still accessible, just slow

**External Nginx Config (Verified - IP-based, NOT the issue):**
```nginx
upstream k8s_workers {
    least_conn;
    server 10.0.64.10:30080;
    server 10.0.64.11:30080;
    server 10.0.64.12:30080;
}
```

**Hypothesis:**
Something in the request path tries hostname resolution first, times out, then falls back to IP. Possible locations:
- Ingress controller internal resolution
- WordPress/PHP making outbound calls
- MariaDB connection (uses hostname?)
- Vault Agent secret refresh attempts
- Some middleware or plugin

**Confounding Factors:**
- Bad WordPress plugin was installed earlier (since removed)
- Plugin caused slowness unrelated to IPA
- Multiple pod restarts observed (may be plugin-related, not IPA-related)

---

## Test Methodology Notes

**Lesson Learned:**
- Forgot to run `kubectl get pods -A -o wide` BEFORE the test
- Pod locations not captured in baseline
- Made it harder to determine if pods moved during outage

**Part 2 Improvement:**
- Capture full pod distribution with `-o wide` before stopping IPA

---

## Part 2 Test Plan

**File:** `tmp-ipa-domain-down-part2.md`

**Pre-requisites before Part 2:**
1. Restore IPA: `ssh root@freeipa 'ipactl start'`
2. Clean restart WordPress pods: `kubectl rollout restart deployment wordpress -n apps`
3. Verify WordPress performance is normal (plugin removed)
4. Remove /etc/hosts fallback entries (clean slate)
5. Document fresh baseline

**Part 2 Objectives:**
- Retest IPA down scenario without any mitigations
- Measure exact WordPress response time impact
- Identify the ~10s delay source
- Test without confounding plugin issues

---

## Conclusions

### Part 1 Findings

1. **K8s cluster survives IPA outage** - kubelet uses IPs internally
2. **/etc/hosts fallback protects node-level** - SSH, kubectl work
3. **/etc/hosts does NOT protect pod-level** - CoreDNS still fails
4. **Vault Agent crashes after ~10min** - DNS retry exhaustion
5. **FluxCD/Helm completely blocked** - No external DNS resolution
6. **Ansible slow when using IPs** - ✅ RESOLVED: SSSD KnownHostsCommand timeout (see TS-IDN-009)
7. **WordPress accessible but slow** - Needs Part 2 investigation

---

## Recommendations

> **Note:** Implement fixes after Part 2 test confirms findings in clean environment.

### Critical Fixes

**1. CoreDNS - Add Fallback Upstream DNS**
```bash
kubectl edit configmap coredns -n kube-system
```
Add fallback to forward plugin:
```
forward . 10.0.60.10 8.8.8.8 {
    policy sequential
}
```
This tries FreeIPA first, falls back to Google DNS.

**2. CoreDNS - Add Static Hosts for Internal Services**
Add hosts plugin to CoreDNS ConfigMap:
```
hosts {
    10.0.62.10  vault1.lab.local vault1
    10.0.62.11  vault2.lab.local vault2
    10.0.62.12  vault3.lab.local vault3
    10.0.62.100 vault.lab.local vault
    fallthrough
}
```
This ensures `vault.lab.local` resolves even if FreeIPA DNS is down.

**3. Ansible Node /etc/hosts**
Add all managed hosts to Ansible node's `/etc/hosts`:
```bash
# Add to ansible/dev/playbooks/common/ or run manually
10.0.61.10-12  k8s-master1/2/3.lab.local
10.0.64.10-12  k8s-worker1/2/3.lab.local
10.0.62.10-12  vault1/2/3.lab.local
```

**4. Terraform VM DNS - Add Fallback**
Update `dns_servers` variable to include public DNS fallback:
```hcl
variable "dns_servers" {
  default = ["10.0.60.10", "8.8.8.8"]
}
```

### Implemented Fixes

**5. Ansible SSH - Disable SSSD KnownHostsCommand** ✅ IMPLEMENTED
Add to all Ansible inventories:
```ini
[all:vars]
ansible_ssh_common_args='-o KnownHostsCommand=none'
```
**Effect:** Prevents 28-second delay when IPA is down.
**TS Case:** `troubleshooting/identity/9-ansible-sssd-knownhosts-timeout.md`

### Optional Improvements

**6. Vault Agent - Use IP Instead of Hostname**
Configure Vault injector to use VIP IP instead of hostname:
```
VAULT_ADDR=https://10.0.62.100:8200
```
Removes DNS dependency entirely for Vault access.
