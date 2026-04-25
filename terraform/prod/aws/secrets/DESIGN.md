# AWS Secrets module — design notes

Why Terraform creates empty secret containers instead of managing the
actual values.

---

## The split: Terraform creates, humans populate

Terraform provisions the 11 Secrets Manager entries with placeholder
values. The actual secret values are populated out-of-band via AWS CLI or
console after `terraform apply`.

This is intentional, not a workaround. The alternative — putting real
secret values in Terraform variables or `.tfvars` — would mean:

- Secrets appear in Terraform state (S3) in plaintext
- Secrets pass through GitHub Actions workflow logs (even with masking,
  they'd be in the plan output)
- Rotating a secret would require a Terraform apply instead of a simple
  AWS CLI `put-secret-value`

By keeping Terraform's job to "create the container" and the human's job
to "fill it," secrets never touch the CI pipeline.

## Why lifecycle ignore_changes on secret_string

Every `aws_secretsmanager_secret_version` has:

```hcl
lifecycle {
  ignore_changes = [secret_string]
}
```

Without this, every `terraform plan` would detect that the actual secret
value differs from the placeholder in the Terraform config and propose
overwriting it. The `ignore_changes` directive tells Terraform: "you
created this resource, but don't track its value after creation."

This is the mechanism that makes the create/populate split work. Terraform
creates with a placeholder, the operator fills the real value, and
Terraform never tries to revert it.

## Why all 11 secrets are in one module

I considered splitting secrets by consumer (Proxmox secrets in one module,
FreeIPA in another, Ansible in another). But the secrets themselves are
just containers — they have no dependencies on other Terraform resources,
no complex logic, and no cross-references. Splitting them would mean 4-5
modules with identical structure, each with its own state file and workflow,
for no architectural benefit.

One module, one `terraform apply`, one place to look. If a secret needs
adding or removing, there's one file to edit.

## Why var.secrets_config uses a structured object

The first version had 11 separate variable blocks (one per secret). That
worked but was noisy — every secret needed the same three fields (name,
description, tags) repeated as separate variables. The `secrets_config`
object map consolidates them into one variable with a consistent shape.
The tradeoff is slightly more complex variable definition, but the main.tf
is cleaner and adding a new secret is one map entry instead of three
variable blocks.
