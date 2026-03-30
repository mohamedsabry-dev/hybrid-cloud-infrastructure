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

---

## Deployment Annotations Used

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
        {{- with secret "secret/data/nginx/config" -}}
        login-password: {{ .Data.data.login-password }}
        {{- end }}
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
This worked but is not acceptable for production — skips all TLS verification.

---

### Error 2 — Attempt to use ConfigMap for CA cert

First attempt used `agent-extra-secret` with a ConfigMap:

```yaml
vault.hashicorp.com/agent-extra-secret: "vault-ca"   # pointing to ConfigMap
vault.hashicorp.com/ca-cert: "/vault/secrets/ca.crt"
```

**Error:**
```
MountVolume.SetUp failed for volume "extra-secrets": secret "vault-ca" not found
```

**Root Cause:** `agent-extra-secret` only works with K8s **Secrets**, not ConfigMaps. The annotation name is misleading.

**Fix:** Converted `vault-ca` from ConfigMap to Secret using `stringData` (plaintext, K8s encodes automatically):

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
    ...
```

---

### Error 3 — Wrong mount path assumption for agent-extra-secret

After converting to Secret, assumed `agent-extra-secret` mounts at `/vault/secrets/ca.crt`:

```yaml
vault.hashicorp.com/ca-cert: "/vault/secrets/ca.crt"
```

**Error:**
```
Error fetching client: failed to setup TLS config: Error loading CA File:
open /vault/secrets/ca.crt: no such file or directory
```

**Investigation:** Checked Vault Agent docs — `agent-extra-secret` actually mounts at `/vault/custom/`. Updated path:

```yaml
vault.hashicorp.com/ca-cert: "/vault/custom/ca.crt"
```

This was still wrong. The correct annotation for TLS CA certs is NOT `agent-extra-secret` at all.

---

### Error 4 — Discovered correct annotation via HashiCorp Discuss

Found in HashiCorp community forum that the dedicated annotation for TLS CA certs is `tls-secret`, not `agent-extra-secret`:

```
vault.hashicorp.com/tls-secret: "vault-ca"    ← mounts at /vault/tls/
vault.hashicorp.com/ca-cert: "/vault/tls/ca.crt"
```

**Why `tls-secret` instead of `agent-extra-secret`:**

| Annotation | Mount Path | Purpose |
|---|---|---|
| `agent-extra-secret` | `/vault/custom/` | AppRole credentials, general secrets |
| `tls-secret` | `/vault/tls/` | TLS CA certificates specifically |

`tls-secret` is the purpose-built annotation for CA cert trust. It mounts the secret at `/vault/tls/` which is where `ca-cert` expects to find it.

---

### Error 5 — Raw KV v2 metadata in secret output

After successful injection, the secret file contained raw API response:

```
data: map[login-password:Change_Me]
metadata: map[created_time:2026-03-29T19:45:26Z custom_metadata:<nil> deletion_time: destroyed:false version:2]
```

**Root Cause:** Without a template, Vault Agent dumps the full KV v2 API response including metadata wrapper.

**Fix:** Add template annotation to extract only the needed value:

```yaml
vault.hashicorp.com/agent-inject-template-config.txt: |
  {{- with secret "secret/data/nginx/config" -}}
  login-password: {{ .Data.data.login-password }}
  {{- end }}
```

Result after fix:
```
login-password: Change_Me
```

---

## Manual Verification Inside Pod

```bash
# Exec into vault-agent sidecar (use sh not bash — minimal image)
kubectl exec -it <pod> -n testing -c vault-agent -- sh

# Check vault directories
ls /vault/
# config  file  logs  secrets  tls

# Verify CA cert is mounted correctly (same symlink structure as ConfigMap)
ls /vault/tls/
# ..2026_03_30_08_44_40.xxx/  ..data/  ca.crt

# Check injected secret
cat /vault/secrets/config.txt
```

**`/vault/file/` directory** — exists by default, empty. Can be used as a pre-defined directory to store files via old-style volumeMount if needed. Not used in this setup.

---

## Vault Directories Reference

```
/vault/
├── config/     ← Vault Agent config (generated by injector)
├── file/       ← empty, available for custom use
├── logs/       ← Vault Agent logs
├── secrets/    ← injected secrets land here (shared with app container)
│   └── config.txt
└── tls/        ← TLS certs mounted via tls-secret annotation
    └── ca.crt
```

---

## Root Cause Summary

1. `agent-extra-secret` only accepts K8s Secrets, not ConfigMaps
2. `agent-extra-secret` mounts at `/vault/custom/` — wrong annotation for CA certs
3. `tls-secret` is the correct annotation for TLS CA certs — mounts at `/vault/tls/`
4. Without a template, Vault Agent dumps raw KV v2 API response including metadata
5. Templates use Go templating — `.Data.data.<key>` to access KV v2 values

---

## Key Annotations Reference

```yaml
# Inject secret (raw output)
vault.hashicorp.com/agent-inject-secret-<filename>: "<vault-path>"

# Inject secret with template (clean output)
vault.hashicorp.com/agent-inject-template-<filename>: |
  {{- with secret "<vault-path>" -}}
  key: {{ .Data.data.<key> }}
  {{- end }}

# TLS CA cert (mounts K8s Secret at /vault/tls/)
vault.hashicorp.com/tls-secret: "<secret-name>"
vault.hashicorp.com/ca-cert: "/vault/tls/ca.crt"

# Skip TLS (lab only, never production)
vault.hashicorp.com/tls-skip-verify: "true"

# Exec into sidecar
kubectl exec -it <pod> -n <ns> -c vault-agent -- sh
```

---

## Related Cases

- Case 63: FreeIPA VIP Certificate SAN — Managedby Permissions
- Case 29: Vault TLS IP SAN Error
