# Deployment Flow

End-to-end order of operations to build an environment from scratch, and the workflows that run each step.

---

## Prerequisite (once per AWS account)

Before any infrastructure workflow can run, the AWS account needs the OIDC
provider and the two GitHub Actions IAM roles in place. That's a one-shot
CloudFormation bootstrap — see [`aws/bootstrap.md`](../aws/bootstrap.md). After
bootstrap, everything below runs via OIDC with no stored AWS credentials.

---

## Full environment deploy order

| # | Workflow | Runner | What it does |
|---|----------|--------|--------------|
| 0 | Manual — AWS Secrets Manager population | — | Populate all secret paths (see [`variables-secrets.md`](variables-secrets.md) for the full list) |
| 1 | `{env}-aws-iam`, `{env}-aws-network`, `{env}-aws-compute`, `{env}-aws-kms-vault-unseal`, `{env}-aws-vault-trust`, `{env}-aws-secrets` | `mac-mini` | AWS side — IAM roles, VPC, WireGuard VPN EC2, KMS for Vault auto-unseal, IAM trust for Vault AWS Secrets Engine, Secrets Manager shells |
| 2 | `{env}-golden-full-setup` | `mac-mini` | Create the golden VM + golden LXC templates on Proxmox |
| 3 | `{env}-proxmox-storage` | `mac-mini` | Mount the NAS on Proxmox |
| 4 | `{env}-ansible-full-setup` | `mac-mini` + `{env}-local-runner` (mixed) | Deploy Ansible LXC → add GitHub deploy key → test clone → run `ansible_setup.yml` |
| 5 | `{env}-local-runner-full-setup` | `mac-mini` + `{env}-local-runner` | Deploy Local Runner LXC → register as GH self-hosted runner → install tools |
| 6 | `{env}-freeipa-full-setup` | `mac-mini` + `{env}-local-runner` | Deploy FreeIPA VM → install IPA server with DNS |
| 7 | Manual: `domain_config.yml`, generate `super_bot` keytab, upload to AWS Secrets | — | One-off setup of users / HBAC / sudo rules + keytab (see [`../deployment-docs/freeipa-initial-setup-guide.txt`](../deployment-docs/freeipa-initial-setup-guide.txt)) |
| 8 | Manual: `add_hosts_to_ipa.yml`, `fix_lxc_krb5_keyring.yml`, `add_dns_records.yml` | — | Domain-join all nodes, fix LXC krb5 ccache, add VIP DNS records |
| 9 | `{env}-nginx-full-setup` | `mac-mini` | Deploy Nginx reverse proxy LXC |
| 10 | `{env}-vault-full-setup` | `mac-mini` + `{env}-local-runner` | Deploy 3-node Vault cluster → install + config via Ansible (AWS KMS auto-unseal) |
| 11 | `{env}-k8s-full-setup` | `mac-mini` + `{env}-local-runner` | Deploy K8s masters → workers → kubeadm init + Flux bootstrap |

Steps 1-3 can run in parallel. Everything from step 4 onward is serial because each depends on what came before it.

---

## Two orderings to be aware of

**"Deployment order"** (above) — the order in which workflows are run to
build the environment. Ansible and Local Runner come very early because
they are the only way to reach the internal network; see
[`../deployment-docs/ansible-runner-setup-guide.txt`](../deployment-docs/ansible-runner-setup-guide.txt)
for the reasoning.

**"Boot order"** (below) — the order Proxmox starts machines at host
power-on or after a DR recovery. FreeIPA must start first because its DNS
and Kerberos are dependencies for every other service's health checks and
identity.

### Boot order (Proxmox)

| # | Host | Why it boots in this slot |
|---|------|---------------------------|
| 1 | `freeipa` | Identity and DNS — everything else depends on this |
| 2 | `ansible` | Control node — needed to repair the fleet if anything else fails |
| 3 | `{env}-local-runner` | CI entry point — restores the ability to re-run workflows automatically |
| 4 | `ex-nginx` | External ingress — needed for any user-facing service |
| 5-7 | `vault1`, `vault2`, `vault3` | Vault HA — needed before K8s pods that consume vault-injected secrets |
| 8-10 | `k8s-master1`, `k8s-master2`, `k8s-master3` | Control plane |
| 11-13 | `k8s-worker1`, `k8s-worker2`, `k8s-worker3` | Workers |

---

## SSH trust chain

Terraform workflows inject the Ansible LXC's SSH public key into every
newly-created node via cloud-init / LXC init. That gives the Ansible node
passwordless SSH into each host once the host comes up:

```
Ansible (10.0.63.10) ──SSH──► freeipa (10.0.60.10)
                      ──SSH──► k8s-master1..3 (10.0.61.10-12)
                      ──SSH──► k8s-worker1..3 (10.0.64.10-12)
                      ──SSH──► vault1..3 (10.0.62.10-12)
                      ──SSH──► ex-nginx (10.0.65.10)
                      ──SSH──► local-runner (10.0.63.20)
```

The Local Runner additionally has SSH into the Ansible node (copied into
`authorized_keys` by the `local-runner-full-setup` workflow), so GitHub
Actions workflows can do: GitHub → Local Runner → SSH to Ansible → run
playbook against the fleet.

For the reasoning behind keeping Ansible and the Local Runner as two
separate LXCs, see
[`../deployment-docs/ansible-runner-setup-guide.txt`](../deployment-docs/ansible-runner-setup-guide.txt).

---

## Related documents

- [`deployment-pattern.md`](deployment-pattern.md) — branch strategy (dev → prod → main) and PR rules
- [`variables-secrets.md`](variables-secrets.md) — full list of GitHub secrets / variables / locks / AWS secrets
- [`../.github/workflows/README.md`](../.github/workflows/README.md) — workflow conventions (OIDC, locks, always-pattern)
- [`../.github/workflows/workflow-guide.txt`](../.github/workflows/workflow-guide.txt) — how to write a new workflow
- [`../deployment-docs/`](../deployment-docs/) — per-service setup guides (freeipa, vault, k8s, ansible/runner)
