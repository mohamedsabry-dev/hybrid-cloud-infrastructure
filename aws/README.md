# AWS Infrastructure

AWS account bootstrap configuration and CloudFormation templates for multi-account architecture.

---

## Directory Structure

```
aws/
├── README.md                    # This file
├── bootstrap.md                 # Detailed bootstrap documentation
├── dev-account-migration.md     # Migration history (eu-west-2 → us-east-1)
└── deployment-stacks/
    ├── bootstrap-dev.yaml       # CloudFormation template (dev account)
    └── bootstrap-prod.yaml      # CloudFormation template (prod account)
```

---

## Quick Reference

### Account Structure

| Environment | Region | State Bucket | Lock Table |
|-------------|--------|--------------|------------|
| Development | us-east-1 | hybrid-cloud-infrastructure-tf-state-dev-v2 | hybrid-cloud-infrastructure-tf-state-lock-dev-v2 |
| Production | eu-west-2 | hybrid-cloud-infrastructure-tf-state-prod | hybrid-cloud-infrastructure-tf-state-lock-prod |

### Bootstrap Resources Created

| Resource | Purpose |
|----------|---------|
| GitHub OIDC Provider | Identity federation for GitHub Actions |
| TerraformPermissionsBoundary | Protects bootstrap resources from modification |
| Terraform State Bucket (S3) | Terraform state storage with versioning |
| Terraform Lock Table (DynamoDB) | State locking for concurrent access |
| GitHubActions-TerraformAdmin Role | Admin role for security branches |
| Admin User (admin_dev/prod) | GUI admin with billing access |

---

## Deployment

### One-Time Bootstrap (per account)

```bash
# Dev (us-east-1) - must be run as root user
aws cloudformation deploy \
    --template-file aws/deployment-stacks/bootstrap-dev.yaml \
    --stack-name bootstrap-dev \
    --capabilities CAPABILITY_NAMED_IAM \
    --region us-east-1

# Prod (eu-west-2) - must be run as root user
aws cloudformation deploy \
    --template-file aws/deployment-stacks/bootstrap-prod.yaml \
    --stack-name bootstrap-prod \
    --capabilities CAPABILITY_NAMED_IAM \
    --region eu-west-2
```

### Update Existing Stack

```bash
# Dev
aws cloudformation update-stack \
    --template-body file://aws/deployment-stacks/bootstrap-dev.yaml \
    --stack-name bootstrap-dev \
    --capabilities CAPABILITY_NAMED_IAM \
    --region us-east-1

# Prod
aws cloudformation update-stack \
    --template-body file://aws/deployment-stacks/bootstrap-prod.yaml \
    --stack-name bootstrap-prod \
    --capabilities CAPABILITY_NAMED_IAM \
    --region eu-west-2
```

---

## IAM Role Architecture

```
2-Tier Role System
│
├── TIER 1: CloudFormation Bootstrap (Manual Deploy)
│   ├── GitHubActions-TerraformAdmin-dev    (branch: dev-security)
│   └── GitHubActions-TerraformAdmin-prod   (branch: prod-security)
│   └── Full admin with PermissionsBoundary protection
│
└── TIER 2: Terraform-Managed (Deployed by TerraformAdmin)
    ├── GitHubActions-Infrastructure-dev    (branch: dev)
    └── GitHubActions-Infrastructure-prod   (branch: prod)
    └── PowerUser access, no IAM mutation
```

---

## Security Features

| Feature | Implementation |
|---------|----------------|
| State Encryption | S3 AES256 server-side encryption |
| TLS Enforcement | Bucket policy denies non-HTTPS |
| Public Access Block | All public access blocked |
| Versioning | Enabled with 90-day expiration |
| State Locking | DynamoDB with deletion protection |
| Permissions Boundary | Prevents modification of bootstrap resources |

---

## Documentation

| Document | Contents |
|----------|----------|
| [bootstrap.md](bootstrap.md) | Full bootstrap architecture, deployment steps, post-setup tasks |
| [dev-account-migration.md](dev-account-migration.md) | Migration guide from eu-west-2 to us-east-1 |

---

## Change Set Inspection (Required Before Every Update)

**ALWAYS verify changes before executing a stack update.** Follow this pattern:

### Step 1: Create Change Set (Console or CLI)

Create change set via AWS Console or CLI - do NOT execute immediately.

### Step 2: Inspect Changes

```bash
# Generic form - replace <STACK_NAME>, <CHANGE_SET_NAME>, <REGION>
aws cloudformation describe-change-set \
    --stack-name <STACK_NAME> \
    --change-set-name <CHANGE_SET_NAME> \
    --region <REGION> \
    --query 'Changes[].ResourceChange.{LogicalId:LogicalResourceId,Action:Action,Details:Details}'
```

### Step 3: Confirm Expected Output

Verify output matches your intended changes. Example of a safe change:

```json
[
    {
        "LogicalId": "TerraformPermissionsBoundary",
        "Action": "Modify",
        "Details": [{
            "Target": {
                "Attribute": "Properties",
                "Name": "PolicyDocument",
                "RequiresRecreation": "Never"
            },
            "ChangeSource": "DirectModification"
        }]
    },
    {
        "LogicalId": "TerraformStateBucket",
        "Action": "Modify",
        "Details": [{
            "Target": {
                "Attribute": "Properties",
                "Name": "LifecycleConfiguration",
                "RequiresRecreation": "Never"
            },
            "ChangeSource": "DirectModification"
        }]
    }
]
```

### Step 4: Execute Only After Confirmation

Only execute the change set after verifying:
- `Action: Modify` (not Delete/Replace)
- `RequiresRecreation: Never`
- `ChangeSource: DirectModification`
- Changed properties match your template edits

---

### Quick Reference Commands

```bash
# Generic form
aws cloudformation describe-change-set --stack-name <STACK_NAME> --change-set-name <CHANGE_SET_NAME> --region <REGION> --query 'Changes[].ResourceChange.{LogicalId:LogicalResourceId,Action:Action,Details:Details}'

# Dev (us-east-1)
aws cloudformation describe-change-set --stack-name bootstrap-dev --change-set-name <CHANGE_SET_NAME> --region us-east-1 --query 'Changes[].ResourceChange.{LogicalId:LogicalResourceId,Action:Action,Details:Details}'

# Prod (eu-west-2)
aws cloudformation describe-change-set --stack-name bootstrap-prod --change-set-name <CHANGE_SET_NAME> --region eu-west-2 --query 'Changes[].ResourceChange.{LogicalId:LogicalResourceId,Action:Action,Details:Details}'
```

### Understanding Change Set Output

| Target.Attribute | Meaning |
|------------------|---------|
| `Tags` | Only tags changing (harmless) |
| `Properties` | Actual resource configuration changing |
| `PolicyDocument` | IAM policy content changing |

### Stack-Level Tags Trigger Changes

> **Note:** Adding tags in the CloudFormation console during stack update (stack-level tags) will propagate to ALL taggable resources. This causes every resource to show `Action: Modify` with `Target.Attribute: Tags`. This is expected and harmless - not an actual infrastructure change.

---

## Troubleshooting

See `/troubleshooting/aws/` for resolved issues:

| Case | Issue |
|------|-------|
| [01](../troubleshooting/aws/1-cloudformation-iam-policy-replacement-failure.md) | IAM policy replacement failure during stack updates |

---

## Related Resources

- **Terraform IAM**: `terraform/dev/aws/iam/` and `terraform/prod/aws/iam/`
- **GitHub Workflows**: `.github/workflows/*-aws-*.yml`
- **GitHub Variables**: Repository Settings → Secrets and variables → Actions
