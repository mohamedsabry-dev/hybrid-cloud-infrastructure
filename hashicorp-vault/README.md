# HashiCorp Vault — narrative hub

Vault is a cross-cutting system in this repo. It's not one layer's concern — it's installed by Ansible, unsealed with infrastructure provisioned by Terraform against AWS KMS, consumed by almost every workload in Kubernetes via the Vault Agent Injector, depended on by FreeIPA (for certs and DNS), tested in disaster-recovery, and automated through GitHub Actions. Nine separate folders in the repo carry a piece of it, and none of them carry the whole.

This folder is the **narrative hub** that ties those pieces together. It does **not** hold code — the playbooks, terraform modules, Helm releases, CA secrets, and CI workflows all stay in their natural layer homes. What lives here is the story, the design decisions, the evolution, and the layer map that says where each implementation piece actually lives. Reading this folder top-to-bottom gives you the shape of the Vault system; then drilling into the layer map gets you to the actual working code.

## What's in here

| File | Purpose |
|------|---------|
| [`DESIGN.md`](DESIGN.md) | The big evolution story in my voice — from POC's raft+no-TLS plan to what's running today: TLS with IPA certs, VIP fronting the 3-node cluster, AWS KMS auto-unseal, and the Kubernetes injector pattern. Reads as a narrative, not a reference. |
| [`kms-unseal.md`](kms-unseal.md) | The AWS KMS auto-unseal story — why I chose KMS over manual/Shamir, the `vault_unseal` IAM user, the credential-injection flow (AWS Secrets Manager → GitHub Actions → Ansible → systemd env), and the `[TS-VLT-003]` empty-credentials incident. |
| [`k8s-integration.md`](k8s-integration.md) | The injection-pattern evolution — how the Vault Agent Injector gets wired into every app, how I landed on the `vault-pod-setup.sh` helper pattern (run once per app: service, pod, ns, sa, secret), and the TS cases that shaped the pattern (`[TS-VLT-004]` TLS CA, `[TS-K8S-014]` SA mismatch, `[TS-K8S-017]` system-namespace injection, `[TS-K8S-033]` DNS failure). |
| [`etcd-backup-role.md`](etcd-backup-role.md) | The AWS Secrets Engine / assume-role chain that lets the etcd-backup CronJob mint temporary AWS credentials via Vault, instead of holding long-lived AWS keys in a Kubernetes secret. The least-documented piece of the story and the one I most want to capture before it drifts. |
| [`cert-regen-cascade.md`](cert-regen-cascade.md) | The `vault.lab.local` VIP certificate cascade — the `managedby` permission on host vs. service objects, the `service-mod` vs. `service-add-managedby` trap (`[TS-VLT-002]`), the SA dependency updates, and why cert regeneration is a multi-layer operation (FreeIPA → Certmonger → Vault reload → Agent sidecars in k8s). |
| [`layer-map.md`](layer-map.md) | **The navigation index.** For every concern — install, unseal, trust, inject, automate, troubleshoot, DR-test — this maps to the real path in the repo where the implementation lives. This is the file to grep when you want to find the code. |

## How to use this folder

**If you're new to the project and want to understand Vault:** Read `README.md` (here) → `DESIGN.md` → `layer-map.md`. That's the shape.

**If you're investigating an incident:** Go to `layer-map.md` → troubleshooting section → click through to the specific TS case.

**If you're extending Vault to a new app:** Go to `k8s-integration.md` → `vault-pod-setup.sh` pattern. Real file at [`../kubernetes/docs/vault-pod-setup.sh`](../kubernetes/docs/vault-pod-setup.sh).

**If you're provisioning a new env:** `layer-map.md` gives you the full deployment order (Terraform → Vault config → K8s setup), with links to the setup guides in `deployment-docs/`.

## What's NOT in here

- **Code.** No playbooks, no `.tf`, no `.yaml`, no scripts. Code lives in its natural layer (`ansible/`, `terraform/`, `kubernetes/`). Moving code here would break the repo's by-function layout and break tooling (ansible-playbook, terraform, flux).
- **Runbooks.** The "how to recover when X breaks" runbooks live in `troubleshooting/vault/` and `disaster-recovery/`. This folder is the *why*, not the *how*.
- **Setup step-by-step.** The ordered deployment guides are in `deployment-docs/` (vault-initial-setup-guide.txt, vault-k8s-integration-guide.txt, k8s-etcd-vault-aws-integration.txt). This folder explains the decisions behind those guides; the guides themselves walk the commands.

## Why this hub exists

Because Vault scattered in my mind the same way it scattered in the repo. The `hashicorp-vault/` folder is the thing I would have wanted when I started this phase of the project — one place to read the evolution, understand the dependencies, and find the pieces without chasing them across nine folders. Writing it was also the thing that forced me to notice which parts of the story I had never formally captured (the etcd-backup assume-role chain most obviously — there's no dedicated doc for that anywhere else in the repo, so this hub is where it lands).
