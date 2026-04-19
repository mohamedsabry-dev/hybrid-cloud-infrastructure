# AWS Configuration

CloudFormation bootstrap for the two AWS accounts backing this hybrid-cloud setup, plus the record of any one-off operations (migrations, account moves, etc.) that needed documenting.

Everything *day-to-day* on AWS — VPC, EC2, IAM roles beyond the bootstrap role, KMS, Secrets Manager — is managed via Terraform under [`../terraform/{env}/aws/`](../terraform/). This folder is for the things Terraform **cannot** manage: the bootstrap itself, and the migration history.

---

## Directory structure

```
aws/
├── README.md                            # This file — landing page + ops reference
├── DESIGN.md                            # Full reasoning: why 2 accounts, 2 state backends, CFN bootstrap, 2-tier IAM, mixed-region prod
├── bootstrap.md                         # Operational: account structure, resources, deploy steps, IAM roles/policies, state isolation
├── dev-account-migration.md             # March 2026: eu-west-2 → us-east-1 migration record
└── deployment-stacks/
    ├── bootstrap-dev.yaml               # CloudFormation template (dev account)
    └── bootstrap-prod.yaml              # CloudFormation template (prod account)
```

Future one-off operations stories (another account migration, a region move, a disaster-recovery rebuild of the bootstrap) should be added here as their own markdown file. This folder is the archive for anything the normal Terraform flow cannot describe.

---

## Where to look

| Question | File |
|----------|------|
| **Why did I design AWS this way?** (2 accounts, 2 state backends, CFN bootstrap, 2-tier IAM, mixed-region prod) | [`DESIGN.md`](DESIGN.md) |
| How do I deploy or update a bootstrap stack? | [`bootstrap.md`](bootstrap.md) — "How to Deploy" + "Post-Bootstrap" sections |
| What are the IAM roles, policies, and state access rules? | [`bootstrap.md`](bootstrap.md) — IAM Roles / Policies / State Access Isolation |
| What did the eu-west-2 → us-east-1 migration look like? | [`dev-account-migration.md`](dev-account-migration.md) |
| What GitHub secrets/vars/AWS secrets feed these workflows? | [`../github/variables-secrets.md`](../github/variables-secrets.md) |
| What workflows use the bootstrap-created roles? | [`../.github/workflows/`](../.github/workflows/) (`*-aws-*.yml` files) |

---

## Change Set Inspection (required before every stack update)

Bootstrap stacks are sensitive — they manage state buckets, admin users, and the permissions boundary that protects everything else. **Never execute a stack update without inspecting the change set first.**

### Step 1 — Create a change set (Console or CLI, do NOT execute immediately)

### Step 2 — Inspect changes

```bash
# Generic form — replace <STACK_NAME>, <CHANGE_SET_NAME>, <REGION>
aws cloudformation describe-change-set \
    --stack-name <STACK_NAME> \
    --change-set-name <CHANGE_SET_NAME> \
    --region <REGION> \
    --query 'Changes[].ResourceChange.{LogicalId:LogicalResourceId,Action:Action,Details:Details}'
```

Per-env quick commands:

```bash
# Dev (us-east-1)
aws cloudformation describe-change-set --stack-name bootstrap-dev \
    --change-set-name <CHANGE_SET_NAME> --region us-east-1 \
    --query 'Changes[].ResourceChange.{LogicalId:LogicalResourceId,Action:Action,Details:Details}'

# Prod (eu-west-2)
aws cloudformation describe-change-set --stack-name bootstrap-prod \
    --change-set-name <CHANGE_SET_NAME> --region eu-west-2 \
    --query 'Changes[].ResourceChange.{LogicalId:LogicalResourceId,Action:Action,Details:Details}'
```

### Step 3 — What to accept / what to reject

Only execute the change set if every row matches:

| What to check | Safe value |
|---------------|------------|
| `Action` | `Modify` — avoid `Delete` or `Replace` on bootstrap resources |
| `RequiresRecreation` | `Never` |
| `ChangeSource` | `DirectModification` |
| `Target.Attribute` | Matches what you actually edited in the YAML |

### Understanding `Target.Attribute`

| Value | Meaning |
|-------|---------|
| `Tags` | Only tags changing — harmless |
| `Properties` | Resource configuration changing — inspect which property |
| `PolicyDocument` | IAM policy content changing — read the diff carefully |

**Heads-up on stack-level tags:** adding a tag in the CloudFormation console during a stack update (a stack-level tag) propagates to every taggable resource. You'll see every resource show `Action: Modify` with `Target.Attribute: Tags`. Expected and harmless, not actual infrastructure change.

---

## Troubleshooting

Real AWS operational incidents I've worked through, documented under [`../troubleshooting/aws/`](../troubleshooting/aws/) — worth checking before you hit similar problems:

| # | File | Gist |
|---|------|------|
| 1 | [`1-cloudformation-iam-projection-failure`](../troubleshooting/aws/1-cloudformation-iam-policy-replacement-failure.md) | CloudFormation IAM policy replacement failing during bootstrap-stack updates — what causes it and how to recover without breaking the PermissionsBoundary |

More cases will land here as they come up — the folder is the canonical record.

Adjacent Terraform-on-AWS cases (security group rename, cloud-init, route tables, etc.) live in [`../troubleshooting/terraform/`](../troubleshooting/terraform/) — worth cross-checking if your issue looks more Terraform-state than AWS-service.

---

## Related

- [`../terraform/{env}/aws/`](../terraform/) — day-to-day AWS resources (VPC, EC2, IAM, KMS, Secrets)
- [`../.github/workflows/`](../.github/workflows/) — `*-aws-*.yml` workflows that consume the bootstrap roles
- [`../github/variables-secrets.md`](../github/variables-secrets.md) — full reference for secrets, vars, AWS Secrets Manager paths
