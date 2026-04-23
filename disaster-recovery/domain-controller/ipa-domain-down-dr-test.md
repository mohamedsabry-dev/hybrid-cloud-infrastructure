# DR Test: IPA Domain Down
# Date: 2026-04-15 to 2026-04-16
# Status: COMPLETED - All Issues Resolved

---

## Executive Summary

This document consolidates the complete IPA Domain Down disaster recovery test conducted over two days. The test identified critical DNS dependencies across the infrastructure and resulted in implementing fixes that ensure service continuity during FreeIPA outages.

### Key Outcomes
| Finding | Impact | Fix | Status |
|---------|--------|-----|--------|
| Vault Agent cannot resolve vault.lab.local | New pods blocked | CoreDNS hosts plugin | RESOLVED |
| External DNS fails (WordPress slow) | 4-12s delays | Node DNS fallback + CoreDNS restart | RESOLVED |
| Ansible 28s delay | Operations slow | KnownHostsCommand=none | RESOLVED |
| Linux nodes no DNS fallback | External resolution fails | zzz-ipa.conf modification | RESOLVED |

---

## 1. Test Scope and Environment

### Objective
Stop FreeIPA server and validate DNS/auth dependencies across the hybrid cloud infrastructure.

### Environment

| Component | Details |
|-----------|---------|
| FreeIPA Server | freeipa.lab.local (10.0.60.10) |
| K8s Masters | k8s-master1/2/3.lab.local (10.0.61.10-12) |
| K8s Workers | k8s-worker1/2/3.lab.local (10.0.64.10-12) |
| K8s API VIP | k8s.lab.local (10.0.61.100) |
| Vault Cluster | vault1/2/3.lab.local (10.0.62.10-12) |
| Vault VIP | vault.lab.local (10.0.62.100) |
| K8s Version | v1.35.3 |
| Vault Version | 1.21.4 |

---

## 2. Pre-Test Baseline

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

## 3. Test Execution Timeline

| Time (EET) | Time (UTC) | Event |
|------------|------------|-------|
| 22:00:49 | 20:00:49Z | IPA stopped |
| 22:01-22:03 | 20:01-20:03Z | Vault Agent DNS errors begin |
| 22:11-22:15 | 20:11-20:15Z | Vault-agent containers crash (exit code 1) |
| 22:30 | 20:30Z | WordPress slowness investigation |
| 22:46 | 20:46Z | Triggered rollout restart (test new pod behavior) |
| 22:46-23:15 | 20:46-21:15Z | New pod stuck in Init:1/2 for 29 minutes |
| 22:51 | 20:51Z | Ansible 28s delay issue discovered |
| 23:17 | 21:17Z | IPA restored |
| 23:20 | 21:20Z | All pods recovered |

---

## 4. Findings Summary

### 4.1 What Works During IPA Outage

| Component | Status | Reason |
|-----------|--------|--------|
| K8s cluster operations | WORKS | kubelet uses IPs internally |
| Existing pods with secrets | WORKS | Already have cached credentials |
| Node SSH (with /etc/hosts) | WORKS | IP-based fallback |
| Vault cluster (internal) | WORKS | Raft uses IPs, /etc/hosts has entries |

### 4.2 What Breaks During IPA Outage

| Component | Status | Root Cause |
|-----------|--------|------------|
| New pod startup | BLOCKED | vault-agent-init cannot resolve vault.lab.local |
| External DNS resolution | FAILS | CoreDNS forwards to FreeIPA only |
| FluxCD/Helm | FAILS | Cannot resolve github.com, chart repos |
| WordPress | SLOW (4-12s) | External API timeouts (Gravatar, api.wordpress.org) |
| Ansible (default) | SLOW (28s) | SSSD KnownHostsCommand timeouts |

---

## 5. Critical Finding: Pod-Level vs Node-Level DNS

### Key Discovery
```
Node level:  /etc/hosts → DNS (/etc/resolv.conf) → Resolution
Pod level:   CoreDNS (10.96.0.10) → /etc/resolv.conf on node → Resolution
```

**Critical insight:** Node `/etc/hosts` entries do NOT help pods. CoreDNS ignores `/etc/hosts`.

### Evidence
```bash
# From k8s-master1 NODE - works via /etc/hosts
[root@k8s-master1]# ping vault.lab.local
PING vault.lab.local (10.0.62.100) 56(84) bytes of data.
64 bytes from vault.lab.local: icmp_seq=1 ttl=63 time=2.94 ms

# From POD (vault-agent) - fails via CoreDNS
dial tcp: lookup vault.lab.local on 10.96.0.10:53: server misbehaving
```

---

## 6. Detailed Findings

### Finding #1: Vault Agent DNS Failure (TS-K8S-033)

**Error Pattern:**
```
agent.auth.handler: error authenticating:
  error="Put \"https://vault.lab.local:8200/v1/auth/kubernetes/login\":
  dial tcp: lookup vault.lab.local on 10.96.0.10:53: server misbehaving"
  backoff=820ms → 1.5s → 2.54s → 4.34s (exponential)
```

**Impact:**
- Running vault-agent sidecars crash after ~10 minutes (exit code 1)
- New pods with vault-agent-init CANNOT start (blocked indefinitely)

**Resolution:** CoreDNS hosts plugin (see Section 7.1)

---

### Finding #2: WordPress External DNS Slowness (TS-K8S-034)

**Symptom:** 4-12 second page load delays

**Evidence:**
```
wp-admin/        200  document   4.27 s
admin-ajax.php   200  xhr        12.16 s
favicon.ico      302  redirect   4.14 s
```

**Root Cause:** WordPress makes external API calls (Gravatar, api.wordpress.org) that timeout when DNS fails.

**Resolution:** Node DNS fallback + CoreDNS restart (see Section 7.2)

---

### Finding #3: Ansible 28-Second Delay (TS-IDN-009)

**Symptom:**
```bash
time ansible ... -m ping
real    0m34.479s   # Expected: <5 seconds
```

**Root Cause:** SSH `KnownHostsCommand` (`/usr/bin/sss_ssh_knownhosts`) attempts SSSD lookups.
- 7-8 SSH connections per Ansible module
- 2 SSSD lookups per connection
- ~2s timeout per lookup
- Total: ~28-34 seconds

**Resolution:** `KnownHostsCommand=none` in Ansible inventory (see Section 7.3)

---

### Finding #4: Linux Nodes No DNS Fallback (TS-LNX-003)

**Symptom:** Nodes only have FreeIPA DNS (10.0.60.10) in resolv.conf.

**Root Cause:** FreeIPA client enrollment creates `/etc/NetworkManager/conf.d/zzz-ipa.conf` with only IPA DNS. The "zzz-" prefix ensures it loads last and overrides all other DNS settings.

**Resolution:** Modify zzz-ipa.conf to include fallback DNS (see Section 7.4)

---

### Finding #5: New Pods Cannot Start During Outage

**Test:** Triggered rollout restart while IPA was down
```bash
kubectl rollout restart deployment wordpress -n apps
```

**Result:** New pod stuck in Init:1/2 for 29 minutes
```
wordpress-7b8c7d879-xbzfr    0/2     Init:1/2   0   29m   # STUCK
```

**Key Insight:** Rolling update strategy protected service availability - old pods kept running.

**Operational Rule:**
> During IPA outage, DO NOT restart/scale deployments that use Vault secrets.

---

## 7. Implemented Solutions

### 7.1 CoreDNS Static Hosts (TS-K8S-033)

**Problem:** Pods cannot resolve vault.lab.local or k8s.lab.local when IPA is down.

**Solution:** Add `hosts` plugin to CoreDNS ConfigMap.

**Implementation:**
```yaml
# kubernetes/dev/deployments/infrastructure/coredns/coredns-custom.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health { lameduck 5s }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        prometheus :9153
        hosts {
            10.0.62.100 vault.lab.local vault
            10.0.61.100 k8s.lab.local k8s
            fallthrough
        }
        forward . /etc/resolv.conf { max_concurrent 1000 }
        cache 30 { disable success cluster.local; disable denial cluster.local }
        loop
        reload
        loadbalance
    }
```

**Apply:**
```bash
kubectl rollout restart deployment coredns -n kube-system
```

**Verification:**
```bash
kubectl run test-dns --rm -it --image=busybox -- nslookup vault.lab.local
# Result: Address: 10.0.62.100
```

---

### 7.2 Linux Nodes DNS Fallback (TS-LNX-003)

**Problem:** Nodes only have FreeIPA DNS, no fallback for external resolution.

**Solution:** Modify `/etc/NetworkManager/conf.d/zzz-ipa.conf` to include 8.8.8.8.

**Implementation:**
```yaml
# playbooks/freeipa/dns_fallback.yml
- name: Add DNS fallback to all IPA clients
  hosts: all:!freeipa
  become: yes
  tasks:
    - name: Add fallback DNS to zzz-ipa.conf
      lineinfile:
        path: /etc/NetworkManager/conf.d/zzz-ipa.conf
        regexp: '^servers='
        line: 'servers=10.0.60.10,8.8.8.8'
        backup: yes

    - name: Restart NetworkManager
      service:
        name: NetworkManager
        state: restarted
```

**Verification:**
```bash
cat /etc/resolv.conf
# nameserver 10.0.60.10
# nameserver 8.8.8.8
```

---

### 7.3 Ansible SSH KnownHostsCommand Fix (TS-IDN-009)

**Problem:** SSSD KnownHostsCommand causes 28-second delays when IPA is down.

**Solution:** Disable KnownHostsCommand in Ansible inventory.

**Implementation:**
```ini
# ansible/dev/inventory/first_setup_inventory.ini
[all:vars]
ansible_ssh_common_args='-o KnownHostsCommand=none'
```

**Verification:**
```bash
time ansible ... -m ping
# Result: 3 seconds (was 34 seconds)
```

---

### 7.4 Vault Auto-Unseal DR Test (TS-LNX-003)

**Critical Test:** Vault can auto-unseal via AWS KMS when IPA is down.

**Test Procedure:**
1. Applied DNS fallback to vault1/2/3
2. Stopped IPA: `ssh root@freeipa 'ipactl stop'`
3. Rebooted all vault nodes
4. Verified vault unsealed via AWS KMS

**Evidence:**
```bash
ping google.com
# PING google.com (142.250.181.142) - WORKS (via 8.8.8.8)

vault status
# Sealed: false
# Seal Type: awskms   # KMS endpoint reached!
```

---

## 8. Files Created/Modified

### New Files
| File | Purpose |
|------|---------|
| `kubernetes/dev/deployments/infrastructure/coredns/coredns-custom.yaml` | CoreDNS static hosts config |
| `kubernetes/dev/deployments/infrastructure/coredns/kustomization.yaml` | Kustomize for CoreDNS |
| `kubernetes/prod/deployments/infrastructure/coredns/coredns-custom.yaml` | Prod CoreDNS config |
| `kubernetes/prod/deployments/infrastructure/coredns/kustomization.yaml` | Prod Kustomize |
| `playbooks/freeipa/dns_fallback.yml` | DNS fallback playbook |

### Modified Files
| File | Change |
|------|--------|
| `kubernetes/dev/deployments/infrastructure/kustomization.yaml` | Added coredns |
| `kubernetes/prod/deployments/infrastructure/kustomization.yaml` | Added coredns |
| `ansible/dev/inventory/first_setup_inventory.ini` | Added KnownHostsCommand=none |

---

## 9. Related Troubleshooting Cases

| Case | Title | Status |
|------|-------|--------|
| TS-K8S-033 | Vault Agent DNS failure + new pod blocking | RESOLVED |
| TS-K8S-034 | WordPress external DNS slowness | RESOLVED |
| TS-K8S-035 | Pod restart investigation (vault-agent vs app) | DOCUMENTED |
| TS-IDN-009 | Ansible SSSD KnownHostsCommand timeout | RESOLVED |
| TS-LNX-003 | Linux nodes DNS fallback | RESOLVED |

---

## 10. Operational Guidelines

### During IPA Outage - DO NOT:
- Restart deployments (`kubectl rollout restart`)
- Scale up pods (`kubectl scale`)
- Delete pods (will attempt reschedule and fail)
- Perform node maintenance (pods cannot reschedule)

### During IPA Outage - SAFE:
- Leave existing pods running (they have cached credentials)
- Monitor pod health
- Use IPs for SSH instead of hostnames
- Wait for IPA restoration

### Critical Warning:
> **Node failure during IPA outage = pods cannot reschedule to other nodes**

---

## 11. Recovery Procedure

```bash
# 1. Start IPA services
ssh root@freeipa 'ipactl start'

# 2. Verify all services running
ssh root@freeipa 'ipactl status'

# 3. Verify DNS resolution restored
nslookup k8s-master1.lab.local

# 4. Pods recover automatically (vault-agent-init completes)
kubectl get pods -A -w
```

**Recovery Time:** Stuck pods recover within seconds after IPA restoration.

---

## 12. Future Recommendations

### Completed
- [x] CoreDNS static hosts for vault.lab.local and k8s.lab.local
- [x] Linux nodes DNS fallback (8.8.8.8)
- [x] Ansible KnownHostsCommand=none
- [x] Vault auto-unseal tested during IPA outage

### Pending (Optional Improvements)
- [ ] Consider IPA high availability (replica server)
- [ ] Configure WordPress to disable external API calls in degraded mode
- [ ] Add caching DNS resolver for external domains
- [ ] Test node failure scenario during IPA outage

---

## 13. Conclusion

The IPA Domain Down DR test successfully identified and resolved all critical DNS dependencies:

1. **Pod DNS Resolution:** CoreDNS hosts plugin ensures vault.lab.local resolves without IPA
2. **Node DNS Resolution:** Fallback DNS (8.8.8.8) ensures external resolution works
3. **Vault Auto-Unseal:** AWS KMS endpoints reachable during IPA outage
4. **Ansible Operations:** KnownHostsCommand=none prevents SSSD timeout delays

**The infrastructure is now resilient to FreeIPA DNS outages for existing workloads.** New pod creation still requires IPA for Kerberos authentication, but this is an acceptable trade-off for the security benefits of centralized identity management.

---

## 14. Document History

| Date | Author | Change |
|------|--------|--------|
| 2026-04-15 | - | Part 1: Initial test, findings documented |
| 2026-04-15 | - | Part 2: Continued testing, Ansible fix |
| 2026-04-16 | - | All fixes implemented and verified |
| 2026-04-16 | - | Combined into final document |
