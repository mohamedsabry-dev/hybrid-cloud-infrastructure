# AWS Compute Module

Provisions WireGuard VPN infrastructure for site-to-site connectivity between AWS and on-premises network.

## Resources Created

| Resource | Name Pattern | Description |
|----------|--------------|-------------|
| `aws_security_group` | `wireguard-sg-{env}` | Security group for WireGuard EC2 |
| `aws_key_pair` | `vpn-key-pair-{env}` | SSH key pair for EC2 access |
| `aws_instance` | `wireguard-{env}` (tag) | WireGuard VPN server (t3.micro) |
| `aws_eip` | `wireguard-eip-{env}` (tag) | Elastic IP for stable public endpoint |
| `aws_route` | - | Route to home network via WireGuard ENI |

## Security Group Rules

| Direction | Protocol | Port | Source | Purpose |
|-----------|----------|------|--------|---------|
| Ingress | UDP | 51820 | `var.allowed_ip` | WireGuard tunnel |
| Ingress | TCP | 22 | `var.allowed_ip` | SSH management |
| Egress | All | All | 0.0.0.0/0 | Outbound traffic |

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `environment` | Environment name | `prod` |
| `aws_region` | AWS region | `eu-west-2` |
| `availability_zone` | AZ for EC2 | `eu-west-2a` |
| `ami_id` | AMI ID (AL2023) | - |
| `instance_type` | EC2 instance type | `t3.micro` |
| `wireguard_port` | WireGuard UDP port | `51820` |
| `home_cidr` | On-prem network CIDR | `10.0.0.0/16` |
| `allowed_ip` | IP allowed for SSH/WG access | *sensitive* |
| `vpn_public_key` | SSH public key | *sensitive* |
| `remote_state_bucket` | S3 bucket for remote state | - |
| `remote_state_region` | Region for state bucket | - |

## Outputs

| Output | Description |
|--------|-------------|
| `wireguard_public_ip` | Public IP of WireGuard server (sensitive) |
| `wireguard_private_ip` | Private IP for VPC routing |
| `wireguard_instance_id` | EC2 instance ID |
| `wireguard_security_group_id` | Security group ID |

## Dependencies

This module requires remote state from:
- `network` module - VPC, subnet, route table IDs
- `iam` module - Instance profile for SSM access

## Usage

```bash
cd terraform/prod/aws/compute
terraform init
terraform plan -var="allowed_ip=x.x.x.x/32" -var="vpn_public_key=ssh-ed25519 ..."
terraform apply
```

## Post-Deployment

After EC2 is provisioned, configure WireGuard:
1. SSH to instance using the EIP
2. Run WireGuard setup script
3. Configure peer on home router
