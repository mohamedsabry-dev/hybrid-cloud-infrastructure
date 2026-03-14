# AWS Dev Account Migration

Migration of dev environment from eu-west-2 (London) to us-east-1 (N. Virginia) in a new AWS account.

**Date:** March 2026 (us-east-1 migration)
**Duration:** ~3 hours

---

## Reasoning

```
Why migrate?
│
├── Trigger: Reserved Instance Purchase Failed
│   ├── Attempted to buy Reserved Instance in old dev account (eu-west-2)
│   ├── Purchase failed with error
│   └── Decision: Migrate to different account instead of troubleshooting
│
├── Cost Optimization
│   ├── US regions are significantly cheaper than London
│   ├── Reserved Instances cheaper in us-east-1
│   ├── Dev account = paid account (no free tier)
│   └── Prod account = has $100+ AWS free tier credits
│
├── Account Separation
│   ├── Dev: Old personal AWS account (repurposed)
│   └── Prod: New AWS account with free tier benefits
│
└── Latency Trade-off (acceptable)
    ├── London → Egypt: ~65ms (prod)
    └── US → Egypt: ~120ms (dev)
    └── Dev latency is acceptable for non-production workloads
```

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

## Lessons Learned

```
Key Takeaways
│
├── S3 Bucket Names
│   └── Deletion takes time to propagate globally
│   └── Use versioned names (-v2) when recreating
│
├── WireGuard Tunnels
│   └── Sometimes a clean slate is faster than debugging
│   └── New EIP + new tunnel entry = fresh start
│
├── Automation Opportunities
│   ├── SSH key pairs can be Terraform-managed
│   ├── Admin users belong in CloudFormation stack
│   └── Reduce manual console operations
│
└── Cost vs Latency
    └── 55ms extra latency is acceptable for dev
    └── Significant cost savings justify the trade-off
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
