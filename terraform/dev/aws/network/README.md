# AWS Network Module

Provisions core AWS networking infrastructure for the hybrid cloud environment.

## Resources Created

| Resource | Name Pattern | Description |
|----------|--------------|-------------|
| VPC | `vpc-main-{env}` (tag) | Main VPC with DNS hostnames enabled |
| Internet Gateway | `igw-main-{env}` (tag) | Internet access for public subnets |
| Subnet (VPN) | `subnet-vpn-{env}` (tag) | Public subnet for WireGuard VPN |
| Subnet (Management) | `subnet-mgmt-{env}` (tag) | Management subnet for internal services |
| Route Table | `rt-public-{env}` (tag) | Public route table with internet route |

## Outputs

| Output | Description | Used By |
|--------|-------------|---------|
| `vpc_id` | VPC ID | Compute module (security groups) |
| `vpc_cidr` | VPC CIDR block | Routing decisions |
| `subnet_vpn_id` | VPN subnet ID | Compute module (EC2 placement) |
| `subnet_mgmt_id` | Management subnet ID | Future services |
| `rt_public_id` | Route table ID | Compute module (home routes) |
| `igw_id` | Internet Gateway ID | Reference |

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `environment` | Environment name | `dev` |
| `aws_region` | AWS region | `us-east-1` |
| `availability_zone` | AZ for subnets | `us-east-1a` |
| `vpc_cidr` | VPC CIDR block | `172.16.0.0/16` |
| `subnet_vpn_cidr` | VPN subnet CIDR | `172.16.65.0/24` |
| `subnet_mgmt_cidr` | Management subnet CIDR | `172.16.63.0/24` |

## Dependencies

- None (base module)

## Dependent Modules

- `compute` - uses VPC, subnet, and route table outputs

## Usage

```bash
cd terraform/dev/aws/network
terraform init
terraform plan
terraform apply
```
