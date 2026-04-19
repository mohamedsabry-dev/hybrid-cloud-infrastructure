# AWS Dev Account Migration

I migrated the dev environment from eu-west-2 (London) to us-east-1 (N. Virginia), into a new AWS account. This doc is the record of what drove the decision and what the migration looked like — kept here as a reference for the next time I need to move an environment between accounts or regions.

**Date:** March 2026
**Duration:** ~3 hours end-to-end

---

## Why I migrated

```
Why migrate?
│
├── Trigger: a Reserved Instance purchase failed
│   ├── I tried to buy a Reserved Instance in the old dev account (eu-west-2)
│   ├── The purchase failed with an error I didn't want to burn time debugging
│   └── Decided: migrate to a different account instead of troubleshooting it
│
├── Cost optimization
│   ├── US regions are significantly cheaper than London for what I run
│   ├── Reserved Instances are cheaper in us-east-1
│   ├── My dev account is a paid account (no free tier left)
│   └── My prod account has $100+ in AWS free tier credits I want to preserve
│
├── Account separation
│   ├── Dev: my old personal AWS account, repurposed for this project
│   └── Prod: a new AWS account with free tier benefits
│
└── Latency trade-off (I accepted this)
    ├── London → Egypt: ~65ms
    └── US → Egypt:     ~120ms
    └── 55ms extra on dev is fine for non-production workloads
```

> **Update (later):** The latency framing above assumed prod would stay in London to keep interactive latency low. That turned out not to survive contact with reality — prod's WireGuard tunnel on the London IP was intermittently unstable (see [`../troubleshooting/network/5-wireguard-tunnel-stability-investigation.md`](../troubleshooting/network/5-wireguard-tunnel-stability-investigation.md)), so I later migrated prod's **network + compute only** (VPC + WireGuard EC2) to `us-east-1`, matching dev's compute region. The rest of prod (state backend, IAM, KMS, vault-trust, secrets) stayed in `eu-west-2`. Full reasoning for the mixed-region result is in [`bootstrap.md`](bootstrap.md) — "Why these regions — and why prod ended up mixed".

---

## Step-by-Step Migration Guide

### Phase 1: Backup (Old Account)

```
Step 1: Backup Everything
│
├── 1.1 Backup Secret Values
│   ├── Export all Secrets Manager values
│   └── Save locally (will recreate in new account)
│
├── 1.2 Backup Terraform State Files
│   ├── Download Proxmox state files from S3
│   │   └── aws s3 cp s3://bucket/dev/proxmox/ ./backup/ --recursive
│   └── Preserve for upload to new bucket
│
└── 1.3 Document Current Config
    └── Note any manual configurations
```

### Phase 2: Destroy Resources (Old Account)

```
Step 2: Terraform Destroy (reverse dependency order)
│
├── Why not manual trigger?
│   └── Main branch has no assume-role authority by design
│   └── Temporarily convert workflows to "terraform destroy"
│
├── 2.1 Destroy Compute
│   └── EC2, EIP, Security Groups, Key Pairs
│
├── 2.2 Destroy Network
│   └── VPC, Subnets, Route Tables, IGW
│
├── 2.3 Destroy Secrets
│   └── Secrets Manager entries
│
├── 2.4 Destroy KMS
│   └── KMS keys (if not protected)
│
└── 2.5 Destroy IAM
    └── Roles, Policies, Instance Profiles
```

### Phase 3: Delete CloudFormation Stack (Old Account)

```
Step 3: Stack Cleanup
│
├── 3.1 Empty S3 Bucket
│   └── Delete all objects and versions
│
├── 3.2 Disable DynamoDB Deletion Protection
│   └── Console → DynamoDB → Table → Edit → Disable deletion protection
│
├── 3.3 Remove DynamoDB Lock Entries
│   └── Delete any remaining LockID items
│
├── 3.4 Delete CloudFormation Stack
│   └── Console → CloudFormation → Delete stack
│
└── 3.5 Manual Cleanup (if needed)
    ├── S3 bucket may remain after stack deletion
    ├── DynamoDB table may remain after stack deletion
    └── Delete manually from console
```

### Phase 4: Setup New Account

```
Step 4: Bootstrap New Account
│
├── 4.1 Update GitHub Variables/Secrets
│   ├── AWS_ACCOUNT_ID_DEV → new account ID
│   └── AWS_REGION_DEV → us-east-1
│
├── 4.2 Update CloudFormation Template (if needed)
│   ├── S3 bucket name (add -v2 if name conflict)
│   └── DynamoDB table name (add -v2 if name conflict)
│
├── 4.3 Deploy CloudFormation Stack
│   ├── Login as root user
│   ├── Console → CloudFormation → Create Stack
│   ├── Upload bootstrap-dev.yaml
│   └── Deploy (wait for completion)
│
├── 4.4 Upload Proxmox State Files
│   └── aws s3 cp ./backup/ s3://new-bucket/dev/proxmox/ --recursive
│
├── 4.5 Recreate All Secrets
│   └── Create secrets in Secrets Manager with backed-up values
│
├── 4.6 Create Password for admin_dev User
│   └── Console → IAM → Users → admin_dev → Security credentials → Create password
│
├── 4.7 Enable IAM Billing Access
│   ├── Login as root user
│   ├── Account → IAM User and Role Access to Billing
│   └── Activate IAM Access
│
└── 4.8 Create CLI Access Key for admin_dev
    ├── Console → IAM → Users → admin_dev → Create access key
    └── aws configure --profile dev
```

### Phase 5: Update Codebase

```
Step 5: Terraform File Updates
│
├── 5.1 Update All provider.tf Files
│   ├── bucket = "new-bucket-name"
│   ├── dynamodb_table = "new-table-name"
│   └── region = "us-east-1"
│
├── 5.2 Update IAM Variables
│   └── dev_account_id = new account ID
│
└── 5.3 Update Compute
    └── ami = region-compatible AMI
```

### Phase 6: Deploy Infrastructure (New Account)

```
Step 6: Terraform Apply (dependency order)
│
├── 6.1 Deploy IAM
│   └── Roles, Policies, Instance Profiles
│
├── 6.2 Deploy KMS
│   └── Encryption keys
│
├── 6.3 Deploy Secrets
│   └── Secrets Manager resources
│
├── 6.4 Deploy Network
│   └── VPC, Subnets, Route Tables
│
└── 6.5 Deploy Compute
    └── EC2, EIP, Security Groups
```

### Phase 7: Validate Proxmox Environment

```
Step 7: Verify Proxmox State
│
├── 7.1 Terraform Init
│   └── cd terraform/dev/proxmox/lxc/ansible && terraform init
│
├── 7.2 Terraform State List
│   └── terraform state list (verify resources exist)
│
└── 7.3 Terraform Plan
    └── terraform plan (should show no changes)
```

### Phase 8: WireGuard Tunnel Setup

```
Step 8: VPN Configuration
│
├── 8.1 SSH to EC2
│   └── ssh -i vpn-key-pair-dev.pem ec2-user@<EIP>
│
├── 8.2 Run WireGuard Setup Script
│   └── ./setup-wireguard.sh dev
│
├── 8.3 Configure ER605 Tunnel
│   ├── Create new tunnel entry
│   ├── Set Peer Public Key (from AWS)
│   ├── Set Peer Endpoint: <EIP>:51820
│   └── Set AllowedIPs
│
├── 8.4 Enter ER605 Public Key in AWS
│   └── Complete the setup script prompt
│
└── 8.5 Verify Tunnel
    ├── sudo wg show
    └── ping <tunnel-ip>
```

### Phase 9: Local CLI Setup

```
Step 9: Admin CLI Configuration
│
├── Purpose: Local Terraform testing without workflows
│
└── Configure AWS Profile:
    aws configure --profile dev
    # Access Key ID: <from admin_dev>
    # Secret Access Key: <from admin_dev>
    # Region: us-east-1
```

---

## Files Changed

```
Repository Changes
│
├── CloudFormation
│   └── aws/deployment-stacks/bootstrap-dev.yaml
│       ├── S3 bucket name → -v2 suffix
│       ├── DynamoDB table name → -v2 suffix
│       └── Added admin_dev user resource
│
├── Terraform Provider Configs (17 files)
│   └── terraform/dev/**/provider.tf
│       ├── S3 bucket → -v2
│       ├── DynamoDB table → -v2
│       └── Region → us-east-1
│
├── Terraform Variables
│   ├── terraform/dev/aws/iam/variables.tf
│   │   └── dev_account_id → new account
│   └── terraform/dev/aws/compute/variables.tf
│       └── Added vpn_public_key variable
│
├── Terraform Resources
│   └── terraform/dev/aws/compute/main.tf
│       ├── Added aws_key_pair resource
│       └── Updated AMI for us-east-1
│
└── GitHub Workflows
    └── .github/workflows/dev-aws-compute.yml
        └── Added -var="vpn_public_key=..." to terraform plan
```

---

## What I learned

```
Key takeaways
│
├── S3 bucket names
│   └── Deletion takes time to propagate globally across AWS
│   └── I used versioned names (-v2 suffix) when recreating to dodge name conflicts
│
├── WireGuard tunnels
│   └── Sometimes a clean slate is faster than debugging an existing tunnel
│   └── New EIP + new tunnel entry = fresh start (same trick I'd use in a DR)
│
├── Automation opportunities I spotted
│   ├── SSH key pairs can be fully Terraform-managed (not manual anymore)
│   ├── Admin users belong inside the CloudFormation bootstrap stack (I moved them there after this migration)
│   └── Goal: minimise manual console operations in any future migration
│
└── Cost vs latency
    └── 55ms extra latency is acceptable for dev
    └── The cost savings justify the trade-off comfortably
```

---

## Post-Migration Verification

```
Checklist
│
├── [x] CloudFormation stack deployed successfully
├── [x] All Terraform resources created
├── [x] WireGuard tunnel operational
├── [x] SSH access to EC2 working
├── [x] Proxmox state files migrated
├── [x] GitHub workflows functional
├── [x] Local AWS CLI configured
└── [x] Ping test: Home ↔ AWS VPC working
```
