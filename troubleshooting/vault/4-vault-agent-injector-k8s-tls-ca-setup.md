# TS-VLT-004 | 2026-03-30 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Vault / Kubernetes
Sub-techs: Vault Agent Injector, Kubernetes, TLS, FreeIPA CA, K8s Secrets,
           ConfigMaps, ServiceAccounts, Go templates, KV v2
Environment: DEV lab.local | K8s cluster | Vault Agent sidecar injection | namespace: testing
Re-opened: No

_____________________________________________________________________

[Issue Description]
Vault Agent injection fails with various TLS and template errors.

Goal: replace hardcoded K8s Secret (nginx-secret) with Vault Agent injection that:
  1. Authenticates to Vault using K8s ServiceAccount token
  2. Fetches secret from secret/data/nginx/config
  3. Writes to /vault/secrets/config.txt inside pod
  4. Verifies Vault TLS cert (signed by FreeIPA CA) — no skip-verify
  5. Auto-refreshes when Vault secret changes — no pod restart needed

7 distinct errors encountered during investigation.

Related ticket: TS-VLT-002 — VIP certificate setup

_____________________________________________________________________

[Analysis]

# Initial Check Notes:

Error 1 — Initial working state with tls-skip-verify:
  vault.hashicorp.com/tls-skip-verify: "true"
  Worked but unacceptable — skips all TLS verification.
  Need proper CA trust with FreeIPA-signed cert.

Error 2 — ConfigMap for CA cert — wrong resource type:
  vault.hashicorp.com/agent-extra-secret: "vault-ca"   (vault-ca was a ConfigMap)
  vault.hashicorp.com/ca-cert: "/vault/secrets/ca.crt"

  kubectl describe pod <pod> -n testing
  Events: MountVolume.SetUp failed for volume "extra-secrets": secret "vault-ca" not found

  Finding: agent-extra-secret only works with K8s Secrets — not ConfigMaps.

  Fix — convert CA cert to K8s Secret:
    apiVersion: v1
    kind: Secret
    metadata:
      name: vault-ca
      namespace: testing
    type: Opaque
    stringData:           # plaintext — K8s base64 encodes automatically
      ca.crt: |
        -----BEGIN CERTIFICATE-----
        ...

Error 3 — Wrong mount path for agent-extra-secret:
  vault.hashicorp.com/ca-cert: "/vault/secrets/ca.crt"

  kubectl logs <pod> -n testing -c vault-agent-init
  Error fetching client: failed to setup TLS config: Error loading CA File:
  open /vault/secrets/ca.crt: no such file or directory

  Checked docs — agent-extra-secret mounts at /vault/custom/ not /vault/secrets/.
  Updated path to /vault/custom/ca.crt — still wrong. agent-extra-secret is not
  the right annotation for TLS CA certs at all.

Error 4 — Discovered correct annotation via HashiCorp community:
  Dedicated annotation for TLS CA certs is tls-secret, not agent-extra-secret.

  vault.hashicorp.com/tls-secret: "vault-ca"       # mounts at /vault/tls/
  vault.hashicorp.com/ca-cert: "/vault/tls/ca.crt"

  Annotation mount path comparison:
    agent-extra-secret  → /vault/custom/   general files, AppRole credentials
    tls-secret          → /vault/tls/      TLS CA certificates specifically

  Verification:
    kubectl exec -it <pod> -n testing -c vault-agent -- sh
    ls /vault/tls/
    → ca.crt present

  Finding: tls-secret is the purpose-built annotation for this use case.

Error 5 — Raw KV v2 metadata dumped without template:
  After TLS fix, injection worked but secret file contained raw API response:
    data: map[login-password:Change_Me]
    metadata: map[created_time:2026-03-29T19:45:26Z custom_metadata:<nil>
    deletion_time: destroyed:false version:2]

  Finding: without template annotation, Vault Agent dumps the full KV v2 API
  response including the metadata wrapper — not just the secret values.

  Fix — add template annotation:
    vault.hashicorp.com/agent-inject-template-config.txt: |
      {{- with secret "secret/data/nginx/config" -}}
      login-password: {{ .Data.data.login-password }}
      {{- end }}

Error 6 — Template parse error: bad character U+002D '-':
  kubectl logs <pod> -n testing -c vault-agent-init
  [ERROR] agent.template.server: template server error:
  error="(dynamic): parse: template: :2: bad character U+002D '-'"
  [ERROR] agent: runtime error encountered: exitCode=1

  Two problems in the template:
    a) Go template engine treats - as subtraction operator.
       .Data.data.login-password is parsed as .Data.data.login MINUS password.
    b) {{- trim markers can conflict with YAML annotation parsing.

  Fix — use index function for hyphenated keys, remove trim markers:
    WRONG:
      {{- with secret "secret/data/nginx/config" -}}
      login-password: {{ .Data.data.login-password }}
      {{- end }}

    CORRECT:
      {{ with secret "secret/data/nginx/config" }}
      login-password: {{ index .Data.data "login-password" }}
      {{ end }}

Error 7 — Secret rendered but showed <no value>:
  /vault/secrets/config.txt:
    login-password: <no value>

  Checked Vault directly:
    vault kv get secret/nginx/config
    Key    Value
    ---    -----
    key    New_Value_From_Vault   ← wrong key name from earlier testing

  Finding: key stored in Vault was named "key" not "login-password".
  Template was correct but key name did not match.

  Fix:
    vault kv put secret/nginx/config login-password="Change_Me"

  Vault Agent auto-refreshed file ~4.5 minutes later without pod restart.


# Suspected Root Cause
Seven independent issues in sequence:
  1. agent-extra-secret only accepts K8s Secrets, not ConfigMaps
  2. agent-extra-secret mounts at /vault/custom/ — wrong annotation for CA certs
  3. tls-secret is the correct annotation for TLS CA — mounts at /vault/tls/
  4. Without template, Vault Agent dumps raw KV v2 API response with metadata
  5. Go template treats - as subtraction — use index for hyphenated key names
  6. {{- trim markers conflict with YAML annotation parsing
  7. Key names in template must exactly match key names stored in Vault


# More Checks Notes:
N/A — all errors encountered and resolved sequentially.


# Suspected Solution
Use tls-secret annotation (not agent-extra-secret) for CA cert.
Use index function for hyphenated keys in templates.
Remove {{- trim markers from templates inside YAML annotations.
Verify key names in Vault match exactly what the template references.


# Test
Applied all fixes, checked vault-agent-init logs and secret file content.

Command:
  kubectl exec -it <pod> -n testing -c nginx -- cat /vault/secrets/config.txt
  vault kv get secret/nginx/config

Result: PASS — config.txt contains correct values, TLS verified, auto-refresh working.

Auto-refresh evidence from vault-agent logs:
  2026-03-30T09:19:15.077Z  agent.auth.handler: authentication successful
  2026-03-30T09:19:15.106Z  agent: (runner) starting  ← initial render on pod start
  2026-03-30T09:23:50.376Z  agent: (runner) rendered "(dynamic)" => "/vault/secrets/config.txt"
  ← ~4.5 minutes later, auto re-rendered after vault kv put without pod restart

_____________________________________________________________________

[Final Root Cause]
Multiple issues combined across 7 steps. Core issues:
  agent-extra-secret is not the correct annotation for TLS CA certs — tls-secret is.
  Go template engine treats hyphen as subtraction — index function required for
  keys with hyphens. Without template annotation, Vault Agent dumps raw KV v2
  response. Key names in template must exactly match keys stored in Vault.

_____________________________________________________________________

[Final Solution]
Complete working Vault Agent injection configuration:

  K8s Secret for CA cert:
    apiVersion: v1
    kind: Secret
    metadata:
      name: vault-ca
      namespace: testing
    type: Opaque
    stringData:
      ca.crt: |
        -----BEGIN CERTIFICATE-----
        <FreeIPA CA certificate>
        -----END CERTIFICATE-----

  Deployment annotations:
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

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: Proper TLS verification setup — no security trade-off.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Vault Agent directory layout:
  /vault/config/    Vault Agent config (generated by injector, do not edit)
  /vault/logs/      Vault Agent logs
  /vault/secrets/   injected secrets (shared volume between sidecar and app)
  /vault/tls/       TLS certs mounted via tls-secret annotation

Template gotchas:
  Hyphenated keys     .Data.data.login-password   WRONG (Go treats - as subtraction)
                      index .Data.data "login-password"   CORRECT
  Trim markers        {{- with ... -}}             can conflict with YAML parsing
                      {{ with ... }}               use without trim markers in annotations
  Missing template    (no annotation)              dumps full KV v2 metadata wrapper
                      add agent-inject-template-*  renders only the values you want

Annotation mount path reference:
  agent-extra-secret  → /vault/custom/   general files, AppRole credentials
  tls-secret          → /vault/tls/      TLS CA certs specifically

Troubleshooting commands:
  kubectl describe pod <pod> -n testing                         mount errors, events
  kubectl logs <pod> -n testing -c vault-agent-init            TLS, auth, template errors
  kubectl logs <pod> -n testing -c vault-agent | grep -i "rendered\|error\|auth"
  kubectl exec -it <pod> -n testing -c vault-agent -- sh       exec into sidecar (use sh)
  kubectl exec -it <pod> -n testing -c nginx -- cat /vault/secrets/config.txt
  vault kv get secret/nginx/config                             verify key names match template
  vault kv put secret/nginx/config login-password="Change_Me"  update and test auto-refresh