# AWS Compute Module — DEV

Provisions the WireGuard VPN EC2 for site-to-site connectivity between AWS
and the on-prem network.

For the "why" — WireGuard vs Site-to-Site VPN, instance sizing, SG
scoping, user_data split — see [`DESIGN.md`](DESIGN.md).

---

## Resources

| Resource | Name / Tag | Description |
|----------|------------|-------------|
| `aws_security_group` | `wireguard-sg-dev` | SG for the WireGuard EC2 |
| `aws_key_pair` | `vpn-key-pair-dev` | SSH key pair for EC2 access |
| `aws_instance` | `wireguard-dev` (Name tag) | WireGuard VPN server (t3.micro, AL2023) |
| `aws_eip` | `wireguard-eip-dev` (Name tag) | Elastic IP for stable public endpoint |
| `aws_route` | — | Route to home CIDR via WireGuard ENI |

## Security group rules

| Direction | Protocol | Port | Source | Purpose |
|-----------|----------|------|--------|---------|
| Ingress | UDP | 51820 | `var.allowed_ip` | WireGuard tunnel |
| Ingress | TCP | 22 | `var.allowed_ip` | SSH management |
| Egress | all | all | 0.0.0.0/0 | Outbound |

## Dependencies (remote state)

- `network` module — VPC + subnet + route-table IDs
- `iam` module — `wireguard_instance_profile_name` for SSM access

## Outputs

| Output | Description |
|--------|-------------|
| `wireguard_public_ip` | EIP (sensitive) |
| `wireguard_private_ip` | Private IP for VPC routing |
| `wireguard_instance_id` | EC2 instance ID |
| `wireguard_security_group_id` | SG ID |

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `environment` | Env name | `dev` |
| `aws_region` | AWS region | `us-east-1` |
| `availability_zone` | AZ for EC2 | `us-east-1a` |
| `ami_id` | AMI ID (AL2023) | — |
| `instance_type` | EC2 instance type | `t3.micro` |
| `wireguard_port` | UDP port | `51820` |
| `home_cidr` | On-prem network CIDR | `10.0.0.0/16` |
| `allowed_ip` | IP allowed for SSH/WG | *sensitive* |
| `vpn_public_key` | SSH public key | *sensitive* |
| `remote_state_bucket` | S3 bucket for remote state | — |
| `remote_state_region` | Region for state bucket | — |

## Related

- [`DESIGN.md`](DESIGN.md) — why WireGuard on EC2, instance sizing, SG scoping, EIP rationale
- [`../../../../deployment-docs/vpn-setup-guide.txt`](../../../../deployment-docs/vpn-setup-guide.txt) — WireGuard install + peer config (post-EC2 setup)
- [`../../../../troubleshooting/terraform/7-security-group-rename-stuck-in-tf-state.md`](../../../../troubleshooting/terraform/7-security-group-rename-stuck-in-tf-state.md) — SG rename gets stuck when attached to EC2 ENI
- [`../../../../.github/workflows/dev-aws-compute.yml`](../../../../.github/workflows/dev-aws-compute.yml) — apply workflow
- [`../network/`](../network/) — upstream VPC + subnet state
- [`../iam/`](../iam/) — upstream instance profile state
