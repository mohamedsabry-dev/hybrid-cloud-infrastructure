# Terraform — Hybrid Cloud Infrastructure

Infrastructure-as-code for both the AWS side of this project (VPCs, IAM, KMS, Secrets Manager, WireGuard VPN EC2) and the on-prem Proxmox side (VMs, LXC containers, golden image templates, NAS storage mounts).

Terraform **provisions** infrastructure. Ansible takes over from there to **configure** what Terraform created.

> **Design notes & reasoning** — for why `dev/` and `prod/` are kept as two separate trees (not workspaces / vars), why Vault is managed by Ansible instead of the Terraform `vault` provider, and the 2-tier IAM model, see [`DESIGN.md`](DESIGN.md).

---

## Directory structure

```
terraform/
├── dev/
│   ├── aws/
│   │   ├── compute/            # WireGuard VPN EC2 + security group + EIP
│   │   ├── iam/                # Infrastructure-dev role + SecurityBoundary + TerraformState policies
│   │   ├── kms-vault-unseal/   # KMS key used by Vault raft auto-unseal
│   │   ├── network/            # VPC + subnets + route tables + Internet Gateway
│   │   ├── secrets/            # Secrets Manager containers (values populated out-of-band)
│   │   └── vault-trust/        # IAM user/role for Vault's AWS Secrets Engine
│   └── proxmox/
│       ├── lxc/
│       │   ├── ansible/        # Ansible control node LXC
│       │   ├── golden-template/ # Golden LXC template (rocky-9-lxc-golden)
│       │   ├── local_runner/   # GitHub Actions self-hosted runner LXC
│       │   ├── nginx/          # External reverse proxy LXC
│       │   └── vault_cluster/  # 3-node Vault LXC cluster (raft)
│       ├── storage/
│       │   └── nas/            # NAS mount configuration
│       └── vms/
│           ├── freeipa/        # FreeIPA VM (identity + DNS)
│           ├── golden-image/   # Golden VM template (rocky-9-vm-golden)
│           ├── k8s_masters/    # 3 K8s master VMs (HA control plane)
│           └── k8s_workers/    # 3 K8s worker VMs (with second NIC on VLAN 40 for CSI-NFS)
└── prod/                       # Mirror of dev with env-specific tokens swapped
    ├── aws/          (same structure as dev)
    └── proxmox/      (same structure as dev, plus:)
        └── vms/testing/       # 2 throwaway VMs for DR break/fix testing (prod only, VLAN 55)
```

Each module has its own `provider.tf` pinning the S3 state backend + DynamoDB lock table. No shared state between modules — each module owns its slice.

## What Terraform does NOT manage

- **AWS bootstrap** (OIDC provider, TerraformAdmin role, state backend, permissions boundary) — CloudFormation, see [`../aws/bootstrap.md`](../aws/bootstrap.md)
- **HashiCorp Vault internal config** — Ansible, see [`DESIGN.md`](DESIGN.md) for the split reasoning
- **Kubernetes workloads** — Flux CD (GitOps), see [`../kubernetes/`](../kubernetes/)
- **Node-level config after provisioning** — Ansible, see [`../ansible/`](../ansible/)

## Versions (pinned per provider)

| Provider | Version pin | Source |
|----------|-------------|--------|
| AWS | `~> 6.28.0` | `hashicorp/aws` |
| Proxmox | `~> 0.96.0` | `bpg/proxmox` |
| External | `~> 2.3.4` | `hashicorp/external` |
| Terraform core | `>= 1.5.0` | — |

Providers are cached on the mac-mini runner at `~/.terraform.d/providers-mirror` — workflows use `terraform init -upgrade` so we always pick up the latest patch version within the pinned constraint without paying the re-download cost on every run.

## Troubleshooting

Real operational cases at [`../troubleshooting/terraform/`](../troubleshooting/terraform/). Worth reading if you're about to touch Proxmox VM disks, rename AWS security groups, or clone an LXC:

| # | Case |
|---|------|
| 1 | Proxmox golden image via Terraform |
| 2 | AWS secrets deletion incident |
| 3 | Terraform-Proxmox LXC clone SSH keys |
| 4 | Terraform-Proxmox cloned VM disk tracking |
| 5 | Terraform-Proxmox LXC mount point bug |
| 6 | Route table — inline vs. `aws_route` resource |
| 7 | Security group rename stuck in Terraform state |
| 8 | Terraform VM disk update behavior |
| 9 | Terraform cloud-init update behavior |
| 10 | Cloud-init SSH host key regeneration |
| 11 | Terraform orphaned disks after removal |

## Related

- [`DESIGN.md`](DESIGN.md) — design notes: why two folders, Vault scope, 2-tier IAM
- [`../aws/bootstrap.md`](../aws/bootstrap.md) — one-time CloudFormation bootstrap that sits outside Terraform
- [`../.github/workflows/README.md`](../.github/workflows/README.md) — GitHub Actions workflow conventions
- [`../github/variables-secrets.md`](../github/variables-secrets.md) — secrets / variables / OIDC reference
- [`../ansible/README.md`](../ansible/README.md) — config management on top of this provisioning
- [`../troubleshooting/terraform/`](../troubleshooting/terraform/) — TS cases (see table above)
