# Vault ↔ Kubernetes integration — the injection pattern

How the Vault Agent Injector gets wired into every workload in the cluster, how I landed on the `vault-pod-setup.sh` helper after repeating the same 7-step per-app setup three times by hand, what the annotation + ServiceAccount + policy + role + CA-secret contract looks like for every consumer app, and the TS cases that shaped each piece. The high-level story is in [`DESIGN.md`](DESIGN.md) — this file is the implementation detail for the "fourth shift" section there.

---

## The overall shape

Vault in this repo is **external to the Kubernetes cluster** — it runs on three LXC containers on Proxmox, not as a Helm release inside k8s. What lives inside the cluster is the **Vault Agent Injector**: a MutatingWebhookConfiguration + a Deployment that, when a pod is created with the right annotations, injects two containers into it:

- An **init container** (`vault-agent-init`) that authenticates to Vault, fetches secrets, renders them to a shared `emptyDir` volume, then exits
- A **sidecar** (`vault-agent`) that stays running, keeps the Vault lease alive, and re-renders secrets if they change (via a template-based notify mechanism)

The app container reads the rendered secrets from the shared volume mount. The app never talks to Vault directly — it talks to files. Vault/secret-management concerns stay entirely in the sidecar.

The injector itself is deployed via the Helm chart at [`../kubernetes/dev/deployments/infrastructure/vault/vault.yaml`](../kubernetes/dev/deployments/infrastructure/vault/vault.yaml) (and prod equivalent), with `server.enabled: false` because the server isn't in the cluster, `injector.enabled: true`, pinned to control-plane nodes, 2 replicas with anti-affinity. The `externalVaultAddr` points at `https://vault.lab.local:8200` — the VIP.

## The 7-step contract per app

Every app that needs a secret goes through the same 7 steps. Variation is minimal (secret paths, role names). This is the pattern the helper script collapses into one interactive run.

### 1. ServiceAccount in the app's namespace

Each app has its **own** SA — not the namespace default. This is the identity Vault's Kubernetes auth method will validate via token review.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: wordpress-sa
  namespace: wordpress
```

### 2. Long-lived token Secret for that SA (K8s 1.24+)

Kubernetes 1.24 changed service-account token handling — SAs no longer auto-generate a long-lived token Secret. But the Vault Agent Injector's init container needs one to present to Vault during auth. So each app SA gets an explicit token Secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: wordpress-sa-token
  namespace: wordpress
  annotations:
    kubernetes.io/service-account.name: wordpress-sa
type: kubernetes.io/service-account-token
```

The `service-account-token` type tells Kubernetes to populate the Secret's `.data.token` with a real, long-lived token bound to the SA. The pattern is the same one used by [`../kubernetes/dev/deployments/infrastructure/vault/vault-auth-sa.yaml`](../kubernetes/dev/deployments/infrastructure/vault/vault-auth-sa.yaml) (the cluster-side `vault-auth` SA used by Vault to *review* tokens — different direction, same mechanism).

### 3. Vault policy

On the Vault side, a policy is written granting read on the app's secret paths:

```hcl
# path in Vault KV v2: secret/data/wordpress/config
path "secret/data/wordpress/config" {
  capabilities = ["read"]
}
```

Policies are scoped per app. No wildcards, no cross-app access. If WordPress's SA gets somehow compromised, the only Vault paths the attacker can read are under `secret/data/wordpress/*` — nothing else in the cluster's secret tree.

### 4. Vault Kubernetes auth role

The auth role binds the SA (from steps 1-2) to the policy (from step 3):

```
vault write auth/kubernetes/role/wordpress \
  bound_service_account_names="wordpress-sa" \
  bound_service_account_namespaces="wordpress" \
  policies="wordpress-policy" \
  ttl="1h"
```

- `bound_service_account_names` and `bound_service_account_namespaces` are the hard gate — Vault's Kubernetes auth method will only issue a token to a JWT that belongs to this SA in this namespace.
- `policies` = what the issued Vault token is allowed to do (read the wordpress config path).
- `ttl="1h"` = Vault-side token lifetime; the sidecar re-auths before expiry.

### 5. Secret data in Vault

The actual secret data has to exist in Vault before the app asks for it. For static secrets (the pattern here — see [`DESIGN.md`](DESIGN.md) for why I didn't use dynamic database secrets):

```
vault kv put secret/wordpress/config \
  db_host="mariadb.mariadb.svc.cluster.local" \
  db_user="wordpress" \
  db_password="<REDACTED>" \
  wordpress_auth_key="..." \
  wordpress_secure_auth_key="..."
```

### 6. IPA CA secret in the app's namespace

The Vault Agent sidecar talks to `https://vault.lab.local:8200`. TLS validation needs the IPA CA cert — the root of trust that signed Vault's cert. Per-namespace secret:

```yaml
# kubernetes/<env>/deployments/apps/wordpress/vault-ca-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: vault-ca
  namespace: wordpress
type: Opaque
data:
  ca.crt: <base64-encoded-IPA-CA-cert>
```

The Injector picks this up via the `vault.hashicorp.com/tls-secret: vault-ca` annotation. Without it, the sidecar's TLS handshake fails on name verification. This was `[TS-VLT-004]` in its original form (see below).

### 7. Annotations on the app Deployment/StatefulSet

The app manifest carries the annotations that trigger injection:

```yaml
spec:
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "wordpress"
        vault.hashicorp.com/tls-secret: "vault-ca"
        vault.hashicorp.com/ca-cert: "/vault/tls/ca.crt"
        vault.hashicorp.com/agent-inject-secret-db-creds: "secret/data/wordpress/config"
        vault.hashicorp.com/agent-inject-template-db-creds: |
          {{- with secret "secret/data/wordpress/config" -}}
          DB_HOST={{ .Data.data.db_host }}
          DB_USER={{ .Data.data.db_user }}
          DB_PASSWORD={{ .Data.data.db_password }}
          {{- end }}
    spec:
      serviceAccountName: wordpress-sa
      ...
```

The injector's webhook sees `vault.hashicorp.com/agent-inject: "true"` during pod admission, injects the init+sidecar containers, configures them to use `role: wordpress` for auth, mounts the `vault-ca` Secret at `/vault/tls/`, and sets up the templates listed in `agent-inject-template-*` annotations. The `agent-inject-secret-*` annotation tells the agent what path to read from; the matching `agent-inject-template-*` tells it how to render.

---

## Why I wrote the `vault-pod-setup.sh` helper

The first app I wired up (MariaDB, probably — the order is blurry now) took about an hour. Most of that hour was going back and forth between:

- The Vault CLI (to write the policy, create the role)
- The k8s manifest file (to add the annotations, the SA, the token secret)
- A scratch file of secret values
- The Helm values (for the app's deployment)
- Vault logs when auth failed

The second app was faster. The third app I hit the same class of mistake — forgot the `bound_service_account_namespaces` field, wrote a policy that referenced `secret/wordpress/*` instead of `secret/data/wordpress/*` (KV v2 vs v1 path syntax), mounted the CA secret at the wrong path, etc. Every one of those mistakes is a 5-minute recovery once you know where to look. Not knowing where to look is what eats the hour.

After the third app, I wrote [`../kubernetes/docs/vault-pod-setup.sh`](../kubernetes/docs/vault-pod-setup.sh). What the script does:

```
1. Prompts for: Vault LDAP username, app name, namespace, SA name
2. Prompts for any number of key=value secret pairs (key in clear, value hidden)
3. Logs into Vault via LDAP
4. Writes the secrets at secret/<app-name>/config using vault kv put
5. Writes a policy <app-name>-policy granting read on secret/data/<app-name>/config
6. Creates a Kubernetes auth role <app-name> bound to the SA+namespace with policy
7. Revokes its own token (cleanup)
```

Every Vault-side step from the 7-step contract collapses into one interactive run. The script is deliberately interactive — I don't pass secrets via CLI args because those show up in shell history (there's a `set +o history` at the top to be extra careful, and `set -o history` at the end to restore).

What the script does **not** do:

- Create the ServiceAccount or token Secret in Kubernetes (steps 1-2). Those are YAML files in the app's manifest folder, committed to git, deployed by Flux. Not the script's job.
- Create the IPA CA Secret (step 6). Same reason.
- Add the annotations to the Deployment (step 7). Same reason.

The script only does the **Vault-side** setup. The cluster-side pieces are GitOps-managed (committed, reviewed, applied by Flux), so they live in manifest files, not in shell scripts.

This split is deliberate: anything that modifies the cluster goes through Flux; anything that modifies Vault goes through a CLI helper. Vault's state isn't in git (it's in raft storage on the Vault nodes), so GitOps can't manage it; a helper script is the best I have for reproducibility.

Apps I've used the script for (matching the catalog):

- WordPress
- MariaDB
- Grafana (via kube-prometheus-stack's helm values)
- The remediation controller
- etcd-backup CronJob (though that one uses the AWS Secrets Engine, not static KV — see [`etcd-backup-role.md`](etcd-backup-role.md))
- The nginx test app

Same pattern, one shell run per app.

---

## The TS cases that shaped the pattern

Every step of the 7-step contract is in the pattern because a previous version of it broke. The TS cases:

### `[TS-VLT-004]` — TLS CA setup / template rendering

File: [`../troubleshooting/vault/4-vault-agent-injector-k8s-tls-ca-setup.md`](../troubleshooting/vault/4-vault-agent-injector-k8s-tls-ca-setup.md)

Two issues bundled together:

1. **Wrong annotation for the CA secret.** I initially used `vault.hashicorp.com/agent-extra-secret: vault-ca` — that annotation mounts an arbitrary secret into the agent but doesn't configure TLS trust. The correct annotation is `vault.hashicorp.com/tls-secret: vault-ca`. Until I fixed this, the sidecar would mount the CA cert but not use it for TLS validation, and the handshake to `vault.lab.local` failed with name verification errors.

2. **Go template hyphen handling.** When a secret key has a hyphen (`login-password`), you can't use the dot notation `.Data.data.login-password` in the agent-inject template — the hyphen is parsed as subtraction. Correct form: `{{ index .Data.data "login-password" }}`. First time I hit this, the template rendered nothing, the sidecar wrote an empty file, the app started with empty creds, failed to reach MariaDB.

Both of these are now baked into the script and the reference annotations in this document.

### `[TS-K8S-014]` — SA name mismatch

File: [`../troubleshooting/kubernetes/14-vault-k8s-auth-service-account-not-authorized.md`](../troubleshooting/kubernetes/14-vault-k8s-auth-service-account-not-authorized.md)

Grafana pod stuck in `Init:1/2`. Vault Agent's init container was failing with:

```
service account name not authorized
```

Root cause: Grafana is deployed via the kube-prometheus-stack Helm chart, which creates its SA with a chart-generated name (`kube-prometheus-stack-grafana`), **not** a custom name like `grafana-sa`. My Vault role had `bound_service_account_names="grafana-sa"` because I hadn't checked what the chart actually named the SA. The SA presenting the JWT was `kube-prometheus-stack-grafana`; Vault rejected because the bind didn't match.

Fix: either rename the Vault role's bound SA to `kube-prometheus-stack-grafana`, or override the chart's `serviceAccount.name` to `grafana-sa`. I chose the second — it's more explicit and survives chart upgrades better.

Lesson: **always verify the actual pod-visible SA name** when using a Helm chart, because the chart may not use what you expect. The helper script doesn't protect against this — it just writes what you type. I learned to `kubectl get sa -n <ns>` first and copy the exact name into the prompt.

### `[TS-K8S-017]` — system-namespace injection

File: [`../troubleshooting/kubernetes/17-vault-injection-system-namespace-denied.md`](../troubleshooting/kubernetes/17-vault-injection-system-namespace-denied.md)

Vault Agent Injector cannot inject into pods in `kube-system` by default — its webhook RBAC excludes system namespaces for safety. This became a problem when I wanted the etcd-backup CronJob to run in `kube-system` (where the etcd access resides).

Fix: grant the injector ClusterRole permission to act on `kube-system`. Done via an additional RBAC rule in the vault Helm values. The risk is real — now the injector CAN modify kube-system pods — but scoped by "only pods with the agent-inject annotation," which are ones I control. Tradeoff accepted.

### `[TS-K8S-033]` — Vault Agent DNS dependency on FreeIPA

File: [`../troubleshooting/kubernetes/33-vault-agent-dns-failure-new-pod-blocking.md`](../troubleshooting/kubernetes/33-vault-agent-dns-failure-new-pod-blocking.md)

When FreeIPA DNS is down (either the IPA server itself, or the CoreDNS upstream config), Vault Agent sidecars can't resolve `vault.lab.local`. Two distinct failure modes:

1. **Running pods** — their sidecars retry resolution, fail, eventually give up after ~10 minutes of retries. Existing Vault tokens stay valid (cached) so the app keeps running for another hour until the token TTL, then fails.
2. **New pods** — can't start. The `vault-agent-init` init container can't reach Vault, can't fetch secrets, never writes the rendered file, the init never completes, the pod sits in `Init:0/1` forever.

This is the whole-cluster Vault Agent outage scenario. It's a symptom of the `FreeIPA is a SPOF` problem (accepted risk documented in [`../disaster-recovery/README.md`](../disaster-recovery/README.md)'s "Known SPOFs" section).

Mitigation options (none implemented yet — just listed for when I revisit this):
- CoreDNS hostAliases entry for `vault.lab.local` → VIP IP, bypassing FreeIPA for Vault resolution
- External DNS resolver for lab.local zones that's independent of the FreeIPA DNS
- Vault Agent caching (cached credentials survive DNS outage longer)

Today the mitigation is "don't take FreeIPA down without planning." Worth noting in this hub because it's the dependency direction most likely to bite.

### `[TS-K8S-024]` — 2-node quorum loss

File: [`../troubleshooting/kubernetes/24-vault-cluster-resilience-2-node-quorum.md`](../troubleshooting/kubernetes/24-vault-cluster-resilience-2-node-quorum.md)

Not strictly a k8s integration issue but cross-ref'd there. 3-node Vault cluster loses leader consensus when 2 nodes are down. This is Raft's design (majority of 3 = 2; with 1 remaining, no quorum, no writes). Not solvable without adding nodes. Listed here because it's a failure mode that affects the injector (no Vault reads/writes = no new pod secrets).

---

## What the app-side manifest looks like end to end

For reference, a minimal end-to-end example — the WordPress case, simplified. Real paths:

- SA + token Secret + Deployment: [`../kubernetes/dev/deployments/apps/wordpress/deployment.yaml`](../kubernetes/dev/deployments/apps/wordpress/deployment.yaml)
- IPA CA for TLS: [`../kubernetes/dev/deployments/apps/wordpress/vault-ca-secret.yaml`](../kubernetes/dev/deployments/apps/wordpress/vault-ca-secret.yaml)

```yaml
# Cluster-side: SA + token Secret (committed, Flux applies these)
apiVersion: v1
kind: ServiceAccount
metadata:
  name: wordpress-sa
  namespace: wordpress
---
apiVersion: v1
kind: Secret
metadata:
  name: wordpress-sa-token
  namespace: wordpress
  annotations:
    kubernetes.io/service-account.name: wordpress-sa
type: kubernetes.io/service-account-token
---
# IPA CA cert for TLS trust
apiVersion: v1
kind: Secret
metadata:
  name: vault-ca
  namespace: wordpress
type: Opaque
data:
  ca.crt: <base64 IPA CA>
---
# Deployment with annotations
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  namespace: wordpress
spec:
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "wordpress"
        vault.hashicorp.com/tls-secret: "vault-ca"
        vault.hashicorp.com/ca-cert: "/vault/tls/ca.crt"
        vault.hashicorp.com/agent-inject-secret-db-creds: "secret/data/wordpress/config"
        vault.hashicorp.com/agent-inject-template-db-creds: |
          {{- with secret "secret/data/wordpress/config" -}}
          DB_HOST={{ .Data.data.db_host }}
          DB_USER={{ .Data.data.db_user }}
          DB_PASSWORD={{ .Data.data.db_password }}
          {{- end }}
    spec:
      serviceAccountName: wordpress-sa
      containers:
        - name: wordpress
          image: wordpress:latest
          envFrom:
            - secretRef:
                name: wordpress-env
          # The rendered db-creds file lives at /vault/secrets/db-creds in the pod.
          # Typically loaded via an entrypoint script that sources it before starting apache.
```

```bash
# Vault-side: run the helper script once
#   app name: wordpress
#   namespace: wordpress
#   SA: wordpress-sa
#   secret keys: db_host, db_user, db_password
# Script writes the policy + role + secret.
```

After both sides are in place:

1. Flux reconciles → SA, token Secret, CA Secret, Deployment all apply.
2. Webhook triggers on Deployment admission → injector adds init + sidecar containers.
3. Init container auths to Vault with SA token, gets policy, reads `secret/data/wordpress/config`, renders the template to `/vault/secrets/db-creds`.
4. App container starts, reads the rendered file, connects to MariaDB.

---

## Related files

- **Injector chart / infra:** [`../kubernetes/dev/deployments/infrastructure/vault/vault.yaml`](../kubernetes/dev/deployments/infrastructure/vault/vault.yaml) / [`../kubernetes/prod/deployments/infrastructure/vault/vault.yaml`](../kubernetes/prod/deployments/infrastructure/vault/vault.yaml)
- **Vault auth SA (cluster-side, for Vault to review tokens):** [`../kubernetes/dev/deployments/infrastructure/vault/vault-auth-sa.yaml`](../kubernetes/dev/deployments/infrastructure/vault/vault-auth-sa.yaml) / [`../kubernetes/prod/deployments/infrastructure/vault/vault-auth-sa.yaml`](../kubernetes/prod/deployments/infrastructure/vault/vault-auth-sa.yaml)
- **Helper script:** [`../kubernetes/docs/vault-pod-setup.sh`](../kubernetes/docs/vault-pod-setup.sh)
- **K8s pre-setup notes:** [`../kubernetes/docs/vault-k8s-pre-setup.txt`](../kubernetes/docs/vault-k8s-pre-setup.txt)
- **Integration playbook (cluster-side):** [`../ansible/dev/playbooks/k8s/integration-vault-k8s-trust.yml`](../ansible/dev/playbooks/k8s/integration-vault-k8s-trust.yml) — sets up the Kubernetes auth method in Vault (registers the token reviewer JWT, sets OIDC config)
- **Setup guide:** [`../deployment-docs/vault-k8s-integration-guide.txt`](../deployment-docs/vault-k8s-integration-guide.txt)
- **Signal flow:** [`../deployment-docs/signal-flows/vault-k8s-auth-signal-flow.txt`](../deployment-docs/signal-flows/vault-k8s-auth-signal-flow.txt)
- **Apps with injection (dev):** wordpress, mariadb, monitoring (grafana), alertmanager, remediation, etcd-backup, testing/nginx-test — each under [`../kubernetes/dev/deployments/apps/`](../kubernetes/dev/deployments/apps/)
- **Apps with injection (prod):** same list minus alertmanager — each under [`../kubernetes/prod/deployments/apps/`](../kubernetes/prod/deployments/apps/)
- **TS cases:** `[TS-VLT-004]`, `[TS-K8S-014]`, `[TS-K8S-017]`, `[TS-K8S-024]`, `[TS-K8S-033]` — see paths in the sections above
