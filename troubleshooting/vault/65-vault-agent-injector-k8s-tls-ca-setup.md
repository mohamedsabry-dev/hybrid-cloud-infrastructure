# Case 65: Vault Agent Injector — K8s TLS CA Trust Setup & Secret Injection

**Component:** HashiCorp Vault | Vault Agent Injector | Kubernetes | FreeIPA CA
**Date:** March 30, 2026

---

## Goal

Replace hardcoded K8s Secret (`nginx-secret`) with Vault Agent injection. The Vault Agent sidecar should:
1. Authenticate to Vault using K8s ServiceAccount token
2. Fetch the secret from `secret/data/nginx/config`
3. Write it to `/vault/secrets/config.txt` inside the pod
4. Verify Vault's TLS cert (signed by FreeIPA CA) properly — no skip-verify
5. Auto-refresh the secret file when Vault secret changes — no pod restart

---

## Final Working Annotations

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

---

## Error Evidence Trail

### Error 1 — Initial working state with tls-skip-verify

First successful injection used:
```yaml
vault.hashicorp.com/tls-skip-verify: "true"
```
This worked but is not acceptable for production — skips all TLS verification entirely.

---

### Error 2 — Attempt to use ConfigMap for CA cert

First attempt used `agent-extra-secret` pointing to a ConfigMap:

```yaml
vault.hashicorp.com/agent-extra-secret: "vault-ca"   # vault-ca was a ConfigMap
vault.hashicorp.com/ca-cert: "/vault/secrets/ca.crt"
```

**Error seen in `kubectl describe pod`:**
```
MountVolume.SetUp failed for volume "extra-secrets": secret "vault-ca" not found
```

**Root Cause:** `agent-extra-secret` only works with K8s **Secrets**, not ConfigMaps. The annotation name is misleading — it says "secret" but the error happens at the volume mount level before Vault is involved at all.

**Fix:** Converted `vault-ca` from ConfigMap to Secret using `stringData`:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: vault-ca
  namespace: testing
type: Opaque
stringData:       # plaintext — K8s base64 encodes automatically on apply
  ca.crt: |
    -----BEGIN CERTIFICATE-----
    ...
```

**TS Commands:**
```bash
kubectl describe pod <pod> -n testing    # shows MountVolume error in Events
kubectl get secret vault-ca -n testing   # verify secret exists
```

---

### Error 3 — Wrong mount path for agent-extra-secret

After converting to Secret, assumed files mount at `/vault/secrets/`:

```yaml
vault.hashicorp.com/ca-cert: "/vault/secrets/ca.crt"
```

**Error seen in vault-agent-init logs:**
```
Error fetching client: failed to setup TLS config: Error loading CA File:
open /vault/secrets/ca.crt: no such file or directory
```

**Investigation:** Checked Vault Agent docs — `agent-extra-secret` mounts at `/vault/custom/` not `/vault/secrets/`. Updated:
```yaml
vault.hashicorp.com/ca-cert: "/vault/custom/ca.crt"
```
This was still wrong — `agent-extra-secret` is not the right annotation for TLS CA certs.

**TS Commands:**
```bash
kubectl logs <pod> -n testing -c vault-agent-init   # shows TLS loading error
kubectl exec -it <pod> -n testing -c vault-agent -- sh
ls /vault/   # config  file  logs  secrets  tls
```

---

### Error 4 — Discovered correct annotation via HashiCorp community

Found via HashiCorp Discuss forum post that the dedicated annotation for TLS CA certs is `tls-secret`, not `agent-extra-secret`.

Source: HashiCorp Discuss — *"Passing a CA certificate to injected vault-agent containers"*

```yaml
vault.hashicorp.com/tls-secret: "vault-ca"       # mounts at /vault/tls/
vault.hashicorp.com/ca-cert: "/vault/tls/ca.crt"
```

**Why `tls-secret` and not `agent-extra-secret`:**

| Annotation | Mount Path | Purpose |
|---|---|---|
| `agent-extra-secret` | `/vault/custom/` | AppRole credentials, general files |
| `tls-secret` | `/vault/tls/` | TLS CA certificates specifically |

`tls-secret` is the purpose-built annotation for this use case. Confirmed by exec into running sidecar:

```bash
kubectl exec -it <pod> -n testing -c vault-agent -- sh
ls /vault/tls/
# ..2026_03_30_08_44_40.xxx/  ..data/  ca.crt   ← same symlink structure as ConfigMap
```

---

### Error 5 — Raw KV v2 metadata dumped without template

After TLS fix, injection worked but secret file contained raw API response:

```
data: map[login-password:Change_Me]
metadata: map[created_time:2026-03-29T19:45:26Z custom_metadata:<nil> deletion_time: destroyed:false version:2]
```

**Root Cause:** Without a template annotation, Vault Agent dumps the full KV v2 API response including the metadata wrapper. This is default behavior.

**Fix:** Add template annotation:
```yaml
vault.hashicorp.com/agent-inject-template-config.txt: |
  {{- with secret "secret/data/nginx/config" -}}
  login-password: {{ .Data.data.login-password }}
  {{- end }}
```

---

### Error 6 — Template parse error: bad character U+002D '-'

After adding the template, vault-agent-init kept failing:

```
[ERROR] agent.template.server: template server error:
error="(dynamic): parse: template: :2: bad character U+002D '-'"
[ERROR] agent: runtime error encountered: exitCode=1
```

**Root Cause:** Go template engine (which Vault Agent uses) treats `-` as a subtraction operator. `.Data.data.login-password` is parsed as `.Data.data.login` **minus** `password` — invalid syntax.

**Source:** HashiCorp knowledge base article *"Vault Agent throws bad character U+002D"*:
> Vault agent templates rely on Consul templating markup which uses the Go template package. The inability to directly use a dash in key values is a known feature gap. The consensus recommendation is to use the `index` function instead.

Also noted: the `{{-` trim markers themselves can also trigger this error when used in certain YAML annotation contexts. Removed both issues:

```yaml
# WRONG — dash in key name AND trim markers cause parse error
vault.hashicorp.com/agent-inject-template-config.txt: |
  {{- with secret "secret/data/nginx/config" -}}
  login-password: {{ .Data.data.login-password }}
  {{- end }}

# CORRECT — use index function for hyphenated keys, no trim markers
vault.hashicorp.com/agent-inject-template-config.txt: |
  {{ with secret "secret/data/nginx/config" }}
  login-password: {{ index .Data.data "login-password" }}
  {{ end }}
```

**TS Commands:**
```bash
kubectl logs <pod> -n testing -c vault-agent-init   # shows template parse error
```

---

### Error 7 — Secret rendered but showed `<no value>`

After template fix, file rendered successfully but output was:
```
login-password: <no value>
```

**Root Cause:** The key stored in Vault was named `key` (from earlier testing), not `login-password`. Template was looking for the right key name but Vault had the wrong one.

**Investigation:**
```bash
vault kv get secret/nginx/config
# Key    Value
# ---    -----
# key    New_Value_From_Vault   ← wrong key name
```

**Fix:** Updated Vault secret to use correct key name:
```bash
vault kv put secret/nginx/config login-password="Change_Me"
```

Vault Agent auto-refreshed the file ~4.5 minutes later without pod restart.

---

## Auto-Refresh Behavior

Vault Agent watches for secret changes and re-renders templates automatically. No pod restart needed.

**Evidence from vault-agent logs:**
```
2026-03-30T09:19:15.077Z [INFO]  agent.auth.handler: authentication successful
2026-03-30T09:19:15.106Z [INFO]  agent: (runner) starting
                                 ↑ pod started, initial render

2026-03-30T09:23:50.376Z [INFO]  agent: (runner) rendered "(dynamic)" => "/vault/secrets/config.txt"
                                 ↑ ~4.5 minutes later, auto re-rendered after secret update
```

**TS Command to watch:**
```bash
kubectl logs <pod> -n testing -c vault-agent | grep -i "rendered\|error"
```

---

## Vault Directories Reference

```
/vault/
├── config/     ← Vault Agent config (generated by injector, do not edit)
├── file/       ← empty by default, available for custom volumeMount use
├── logs/       ← Vault Agent logs
├── secrets/    ← injected secrets (shared volume between sidecar and app)
│   └── config.txt
└── tls/        ← TLS certs mounted via tls-secret annotation
    └── ca.crt  ← same symlink structure as K8s ConfigMap mount
```

---

## Key TS Commands

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

---

## Root Cause Summary

1. `agent-extra-secret` only accepts K8s Secrets not ConfigMaps
2. `agent-extra-secret` mounts at `/vault/custom/` — wrong annotation for CA certs
3. `tls-secret` is the correct annotation for TLS CA — mounts at `/vault/tls/`
4. Without a template, Vault Agent dumps raw KV v2 API response including metadata
5. Go template engine treats `-` as subtraction operator — use `index` for hyphenated keys
6. `{{-` trim markers can conflict with YAML annotation parsing — remove them
7. Key names in template must exactly match key names stored in Vault

---

## Related Cases

- Case 63: FreeIPA VIP Certificate SAN — Managedby Permissions
- Case 29: Vault TLS IP SAN Error
