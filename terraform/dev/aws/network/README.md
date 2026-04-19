# AWS Network Module — DEV

Provisions the core AWS networking for the hybrid-cloud environment: VPC,
Internet Gateway, public subnet (VPN-facing), management subnet, and the
public route table.

---

## Resources

| Resource | Name / Tag | Description |
|----------|------------|-------------|
| VPC | `vpc-main-dev` | Main VPC with DNS hostnames enabled |
| Internet Gateway | `igw-main-dev` | Internet access for public subnets |
| Subnet (VPN) | `subnet-vpn-dev` | Public subnet for the WireGuard VPN EC2 |
| Subnet (Management) | `subnet-mgmt-dev` | Management subnet for internal services |
| Route Table | `rt-public-dev` | Public route table with internet route |

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `environment` | Env name | `dev` |
| `aws_region` | AWS region | `us-east-1` |
| `availability_zone` | AZ for subnets | `us-east-1a` |
| `vpc_cidr` | VPC CIDR | `172.16.0.0/16` |
| `subnet_vpn_cidr` | VPN subnet CIDR | `172.16.65.0/24` |
| `subnet_mgmt_cidr` | Management subnet CIDR | `172.16.63.0/24` |

## Outputs

| Output | Description | Consumer |
|--------|-------------|----------|
| `vpc_id` | VPC ID | `compute` module (security groups) |
| `vpc_cidr` | VPC CIDR block | Routing decisions |
| `subnet_vpn_id` | VPN subnet ID | `compute` module (EC2 placement) |
| `subnet_mgmt_id` | Management subnet ID | Future services |
| `rt_public_id` | Route table ID | `compute` module (home routes) |
| `igw_id` | IGW ID | Reference |

## Dependencies

- None (base module)

## Dependent modules

- `compute` — consumes VPC + subnet + route-table outputs

## Related

- [`../../../../.github/workflows/dev-aws-network.yml`](../../../../.github/workflows/dev-aws-network.yml) — apply workflow
- [`../../../../deployment-docs/network-setup-guide.txt`](../../../../deployment-docs/network-setup-guide.txt) — broader network setup (on-prem + AWS)
