# TS-VLT-004 | 2026-03-30 | RESOLVED

## 1. Context
- System: Vault Agent Injector / Kubernetes / TLS
- Environment: K8s cluster with Vault Agent sidecar injection
- Related components: Vault Agent Injector, FreeIPA CA, K8s ServiceAccounts, ConfigMaps/Secrets
- Related tickets: [TS-VLT-002](2-freeipa-vip-certificate-san-managedby.md) - VIP certificate setup

## 2. Issue
- Symptom: Vault Agent injection fails with various TLS and template errors
- Goal: Replace hardcoded K8s Secret (`nginx-secret`) with Vault Agent injection that:
  1. Authenticates to Vault using K8s ServiceAccount token
  2. Fetches secret from `secret/data/nginx/config`
  3. Writes to `/vault/secrets/config.txt` inside pod
  4. Verifies Vault's TLS cert (signed by FreeIPA CA) - no skip-verify
  5. Auto-refreshes when Vault secret changes - no pod restart

**Final Working Annotations:**
```yaml
template:
  metadata:
    annotations:
      vault.hashicorp.com/agent-inject: "true"
      vault.hashicorp.com/role: "nginx"
      vault.hashicorp.com/agent-inject-secret-config.txt: "secret/data/nginx/config"
      vault.hashicorp.com/tls-skip-verify: "false"
      vault.hashicorp.com/tls-secret: "vault-ca"
      vault.hashicorp.com/ca-cert: "/vault/tls/ca.crt"
      vault.hashicorp.com/agent-inject-template-config.txt: |
        {{ with secret "secret/data/nginx/config" }}
        login-password: {{ index .Data.data "login-password" }}
        {{ end }}
  spec:
    serviceAccountName: nginx-sa
```

## 3. Analysis

**7 distinct errors encountered during investigation:**

---

**Error 1: Initial working state with tls-skip-verify**
```yaml
vault.hashicorp.com/tls-skip-verify: "true"
```
Finding: Worked but unacceptable for production - skips all TLS verification. Need proper CA trust. ✓

---

**Error 2: ConfigMap for CA cert - wrong resource type**
```yaml
vault.hashicorp.com/agent-extra-secret: "vault-ca"   # vault-ca was a ConfigMap
vault.hashicorp.com/ca-cert: "/vault/secrets/ca.crt"
```

```bash
kubectl describe pod <pod> -n testing
# Events:
# MountVolume.SetUp failed for volume "extra-secrets": secret "vault-ca" not found
```

Finding: `agent-extra-secret` only works with K8s **Secrets**, not ConfigMaps.

**Fix:** Convert from ConfigMap to Secret:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: vault-ca
  namespace: testing
type: Opaque
stringData:       # plaintext — K8s base64 encodes automatically
  ca.crt: |
    -----BEGIN CERTIFICATE-----
    ...
```

---

**Error 3: Wrong mount path for agent-extra-secret**
```yaml
vault.hashicorp.com/ca-cert: "/vault/secrets/ca.crt"
```

```bash
kubectl logs <pod> -n testing -c vault-agent-init
# Error fetching client: failed to setup TLS config: Error loading CA File:
# open /vault/secrets/ca.crt: no such file or directory
```

Finding: Checked Vault Agent docs - `agent-extra-secret` mounts at `/vault/custom/` not `/vault/secrets/`.

Updated to `/vault/custom/ca.crt` but still wrong - `agent-extra-secret` is not the right annotation for TLS CA certs.

---

**Error 4: Discovered correct annotation via HashiCorp community**

Found via HashiCorp Discuss forum that dedicated annotation for TLS CA certs is `tls-secret`, not `agent-extra-secret`.

```yaml
vault.hashicorp.com/tls-secret: "vault-ca"       # mounts at /vault/tls/
vault.hashicorp.com/ca-cert: "/vault/tls/ca.crt"
```

**Mount path comparison:**
| Annotation | Mount Path | Purpose |
|---|---|---|
| `agent-extra-secret` | `/vault/custom/` | AppRole credentials, general files |
| `tls-secret` | `/vault/tls/` | TLS CA certificates specifically |

**Verification:**
```bash
kubectl exec -it <pod> -n testing -c vault-agent -- sh
ls /vault/tls/
# ..2026_03_30_08_44_40.xxx/  ..data/  ca.crt
```
Finding: `tls-secret` is purpose-built annotation for this use case. ✓

---

**Error 5: Raw KV v2 metadata dumped without template**

After TLS fix, injection worked but secret file contained raw API response:
```
data: map[login-password:Change_Me]
metadata: map[created_time:2026-03-29T19:45:26Z custom_metadata:<nil> deletion_time: destroyed:false version:2]
```

Finding: Without template annotation, Vault Agent dumps full KV v2 API response including metadata wrapper.

**Fix:** Add template annotation:
```yaml
vault.hashicorp.com/agent-inject-template-config.txt: |
  {{- with secret "secret/data/nginx/config" -}}
  login-password: {{ .Data.data.login-password }}
  {{- end }}
```

---

**Error 6: Template parse error - bad character U+002D '-'**
```bash
kubectl logs <pod> -n testing -c vault-agent-init
# [ERROR] agent.template.server: template server error:
# error="(dynamic): parse: template: :2: bad character U+002D '-'"
# [ERROR] agent: runtime error encountered: exitCode=1
```

Finding: Go template engine treats `-` as subtraction operator. `.Data.data.login-password` parsed as `.Data.data.login` **minus** `password`.

Also: `{{-` trim markers can conflict with YAML annotation parsing.

**Fix:** Use `index` function for hyphenated keys, remove trim markers:
```yaml
# WRONG — dash in key name AND trim markers cause parse error
vault.hashicorp.com/agent-inject-template-config.txt: |
  {{- with secret "secret/data/nginx/config" -}}
  login-password: {{ .Data.data.login-password }}
  {{- end }}

# CORRECT — use index function, no trim markers
vault.hashicorp.com/agent-inject-template-config.txt: |
  {{ with secret "secret/data/nginx/config" }}
  login-password: {{ index .Data.data "login-password" }}
  {{ end }}
```

---

**Error 7: Secret rendered but showed `<no value>`**
```
login-password: <no value>
```

Finding: Key stored in Vault was named `key` (from earlier testing), not `login-password`.

```bash
vault kv get secret/nginx/config
# Key    Value
# ---    -----
# key    New_Value_From_Vault   ← wrong key name
```

**Fix:** Update Vault secret:
```bash
vault kv put secret/nginx/config login-password="Change_Me"
```

Vault Agent auto-refreshed file ~4.5 minutes later without pod restart.

## 4. Root Cause
> Multiple issues combined:
> 1. `agent-extra-secret` only accepts K8s Secrets not ConfigMaps
> 2. `agent-extra-secret` mounts at `/vault/custom/` - wrong annotation for CA certs
> 3. `tls-secret` is correct annotation for TLS CA - mounts at `/vault/tls/`
> 4. Without template, Vault Agent dumps raw KV v2 API response including metadata
> 5. Go template engine treats `-` as subtraction operator - use `index` for hyphenated keys
> 6. `{{-` trim markers can conflict with YAML annotation parsing
> 7. Key names in template must exactly match key names stored in Vault

## 5. Solution
> Use correct annotations: `tls-secret` for CA cert, `index` function for hyphenated keys in templates.

**Complete working deployment:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: vault-ca
  namespace: testing
type: Opaque
stringData:
  ca.crt: |
    -----BEGIN CERTIFICATE-----
    <FreeIPA CA certificate content>
    -----END CERTIFICATE-----
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: testing
spec:
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "nginx"
        vault.hashicorp.com/agent-inject-secret-config.txt: "secret/data/nginx/config"
        vault.hashicorp.com/tls-skip-verify: "false"
        vault.hashicorp.com/tls-secret: "vault-ca"
        vault.hashicorp.com/ca-cert: "/vault/tls/ca.crt"
        vault.hashicorp.com/agent-inject-template-config.txt: |
          {{ with secret "secret/data/nginx/config" }}
          login-password: {{ index .Data.data "login-password" }}
          {{ end }}
    spec:
      serviceAccountName: nginx-sa
      containers:
      - name: nginx
        image: nginx:latest
```

## 6. Solution Risk
- Risk level: LOW
- Potential impact: None - proper TLS verification setup

## 7. Impact After Fix
- Observed: Vault Agent injects secrets with proper TLS verification
- Auto-refresh working (verified ~4.5 min after secret update)
- No pod restart needed for secret changes

**Auto-Refresh Evidence from vault-agent logs:**
```
2026-03-30T09:19:15.077Z [INFO]  agent.auth.handler: authentication successful
2026-03-30T09:19:15.106Z [INFO]  agent: (runner) starting
                                 ↑ pod started, initial render

2026-03-30T09:23:50.376Z [INFO]  agent: (runner) rendered "(dynamic)" => "/vault/secrets/config.txt"
                                 ↑ ~4.5 minutes later, auto re-rendered after secret update
```

## 8. Notes

**Vault Agent Directories:**
```
/vault/
├── config/     ← Vault Agent config (generated by injector, do not edit)
├── file/       ← empty by default, available for custom volumeMount use
├── logs/       ← Vault Agent logs
├── secrets/    ← injected secrets (shared volume between sidecar and app)
│   └── config.txt
└── tls/        ← TLS certs mounted via tls-secret annotation
    └── ca.crt
```

**Key TS Commands:**
```bash
# Check pod events (mount errors, scheduling)
kubectl describe pod <pod> -n testing

# Check init container logs (TLS, auth, template errors)
kubectl logs <pod> -n testing -c vault-agent-init

# Check sidecar logs (render events, renewal, errors)
kubectl logs <pod> -n testing -c vault-agent | grep -i "rendered\|error\|auth"

# Exec into vault-agent sidecar (use sh not bash — minimal image)
kubectl exec -it <pod> -n testing -c vault-agent -- sh

# Exec into nginx container to verify secret file
kubectl exec -it <pod> -n testing -c nginx -- cat /vault/secrets/config.txt

# Check what's in Vault (verify key names match template)
vault kv get secret/nginx/config

# Update Vault secret
vault kv put secret/nginx/config login-password="Change_Me"
```

**Template Gotchas:**
| Issue | Wrong | Correct |
|-------|-------|---------|
| Hyphenated keys | `.Data.data.login-password` | `index .Data.data "login-password"` |
| Trim markers in YAML | `{{- with ... -}}` | `{{ with ... }}` |
| Missing template | (dumps raw metadata) | Add `agent-inject-template-*` |

## 9. Workaround (if any)
> `vault.hashicorp.com/tls-skip-verify: "true"` - works but NOT recommended for production.

