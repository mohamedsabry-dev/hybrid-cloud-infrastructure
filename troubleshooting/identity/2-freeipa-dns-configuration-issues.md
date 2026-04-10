# TS-IDN-002 | 2026-03-05 | RESOLVED

## 1. Context
- System: FreeIPA / BIND DNS
- Environment: DEV (lab.local)
- Related components: FreeIPA server (freeipa.lab.local), all domain clients

## 2. Issue
- Symptom: Clients joined to FreeIPA domain cannot resolve external domains
- Error:
```bash
# From client (e.g., vault1.lab.local) - external DNS fails
dig @10.0.60.10 google.com
;; ->>HEADER<<- opcode: QUERY, status: REFUSED, id: 12345
;; flags: qr rd; QUERY: 1, ANSWER: 0, AUTHORITY: 0, ADDITIONAL: 1
;; WARNING: recursion requested but not available
;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 4096
; EDE: 18 (Prohibited)

# From FreeIPA server itself - works fine
dig google.com
# Returns valid response
```

## 3. Analysis

**Check 1: Are forwarders configured in FreeIPA?**
```bash
# On FreeIPA server
ipa dnsconfig-show
```
Result: Empty configuration - despite setting `ipaserver_forwarders` in playbook vars, forwarders were not applied by the role.

**Check 2: Why does it work from FreeIPA server but not clients?**

BIND defaults to allowing recursion only from localhost (127.0.0.1). When client (10.0.x.x) asks FreeIPA DNS "What's the IP of google.com?":
1. FreeIPA DNS doesn't know google.com directly
2. It needs to ask upstream DNS (forwarders) - this is "recursion"
3. BIND only allows recursion from 127.0.0.1
4. Clients get REFUSED

## 4. Root Cause
> Two problems:
> 1. **Forwarders not applied:** The `ipaserver_forwarders` var in the role didn't configure DNS forwarders properly
> 2. **Recursion denied:** BIND defaults to allowing recursion only from localhost (127.0.0.1)

## 5. Solution
> Add `post_tasks` to FreeIPA setup playbook to configure forwarders and allow recursion from internal networks.

**Why this works:** We manually configure DNS forwarders (8.8.8.8, 1.1.1.1) using the ipadnsconfig module, and tell BIND to allow recursive queries from our internal network (10.0.0.0/8).

**File:** `ansible/dev/playbooks/freeipa/freeipa_setup.yml`

**Location:** On FreeIPA server (freeipa.lab.local)

**Added in post_tasks section:**
```yaml
post_tasks:
  - name: Configure DNS forwarders
    freeipa.ansible_freeipa.ipadnsconfig:
      ipaadmin_password: "{{ ipaadmin_password }}"
      forwarders:
        - ip_address: 8.8.8.8
        - ip_address: 1.1.1.1
      forward_policy: first
      allow_sync_ptr: yes

  - name: Allow DNS recursion from internal networks
    ansible.builtin.blockinfile:
      path: /etc/named/ipa-options-ext.conf
      block: |
        allow-recursion { 127.0.0.1; 10.0.0.0/8; };
        allow-query-cache { 127.0.0.1; 10.0.0.0/8; };
      marker: "# {mark} ANSIBLE MANAGED - DNS RECURSION"
      create: yes
      owner: root
      group: named
      mode: '0640'
    notify: Restart named

handlers:
  - name: Restart named
    ansible.builtin.service:
      name: named
      state: restarted
```

**Config file edited:** `/etc/named/ipa-options-ext.conf` (on FreeIPA server)

**Verification:**
```bash
# On FreeIPA server - check forwarders are set
ipa dnsconfig-show
  Global forwarders: 8.8.8.8, 1.1.1.1
  Forward policy: first

# On FreeIPA server - check BIND config
cat /etc/named/ipa-options-ext.conf
# BEGIN ANSIBLE MANAGED - DNS RECURSION
allow-recursion { 127.0.0.1; 10.0.0.0/8; };
allow-query-cache { 127.0.0.1; 10.0.0.0/8; };
# END ANSIBLE MANAGED - DNS RECURSION

# From client - test external resolution
dig @10.0.60.10 google.com
# Should return A record
```

## 6. Solution Risk
- Risk level: LOW
- Potential impact: Opening recursion to 10.0.0.0/8 - acceptable for internal network, would be risk if FreeIPA DNS exposed to internet

## 7. Impact After Fix
- Observed: All clients can resolve external domains
- No new issues caused

## 8. Notes

**IMPORTANT:** Use `/etc/named/ipa-options-ext.conf` (included inside BIND options block), NOT `/etc/named/ipa-ext.conf` which is outside the options context.

**Forwarders syntax gotcha:**
```yaml
# WRONG - plain strings (causes "dictionary requested" error)
forwarders:
  - 8.8.8.8
  - 1.1.1.1

# CORRECT - dictionary with ip_address key
forwarders:
  - ip_address: 8.8.8.8
  - ip_address: 1.1.1.1
```

The ansible-freeipa module expects dictionaries because it supports additional options like port:
```yaml
forwarders:
  - ip_address: 8.8.8.8
    port: 53           # optional
```

## 9. Workaround (if any)
> Manual configuration on FreeIPA server:
> ```bash
> # Add forwarders via IPA CLI
> ipa dnsconfig-mod --forwarder=8.8.8.8 --forwarder=1.1.1.1
>
> # Edit BIND config
> vi /etc/named/ipa-options-ext.conf
> # Add: allow-recursion { 127.0.0.1; 10.0.0.0/8; };
>
> # Restart named
> systemctl restart named
> ```

## References
- [FreeIPA DNS Configuration](https://freeipa.readthedocs.io/en/latest/designs/dns.html)
- [BIND allow-recursion](https://bind9.readthedocs.io/en/latest/reference.html)
