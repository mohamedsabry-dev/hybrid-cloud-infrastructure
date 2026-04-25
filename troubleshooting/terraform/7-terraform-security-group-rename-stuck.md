# TS-TF-007 | 2026-03-21 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Terraform / AWS
Sub-techs: Terraform AWS provider, security groups, ENI, EC2, create_before_destroy,
           immutable attribute replacement
Environment: AWS EC2
Re-opened: No

_____________________________________________________________________

[Issue Description]
terraform apply stuck on "Still destroying..." for security group — no progress
after 2+ minutes, eventually times out.

  aws_security_group.wireguard: Still destroying... [id=sg-07d51802e9ca80234, 01m30s elapsed]
  aws_security_group.wireguard: Still destroying... [id=sg-07d51802e9ca80234, 01m40s elapsed]
  aws_security_group.wireguard: Still destroying... [id=sg-07d51802e9ca80234, 01m50s elapsed]

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Checked what operation Terraform was attempting.

Terraform plan showed -/+ (destroy and create replacement):
  -/+ resource "aws_security_group" "wireguard" {
        ~ name = "dev-wireguard-sg" -> "wireguard-sg-dev"  # forces replacement

Security group name is immutable — changing it forces resource replacement.
Terraform default behaviour for replacement: destroy old first, then create new.

Why deletion is stuck:
  AWS cannot delete a security group that is attached to an ENI.
  The EC2 instance still references the old SG via its network interface.
  AWS refuses the deletion request → Terraform stuck in a loop waiting.


# Suspected Root Cause
Security group name change triggers replace (-/+). Terraform attempts
delete-before-create by default. AWS refuses deletion because the SG is still
attached to the EC2 instance ENI. Terraform waits indefinitely for deletion
that can never succeed while the instance holds the attachment.


# More Checks Notes:
N/A — cause and fix direction clear from AWS behaviour.


# Suspected Solution
Manual fix for stuck apply: temporarily detach SG from instance so deletion
can proceed. Prevention for future renames: create_before_destroy lifecycle.


# Test
Assigned default VPC security group to EC2 instance while Terraform was stuck.
Terraform immediately continued — deleted old SG, created new SG, updated EC2.

Result: PASS — apply completed, EC2 using new security group.

_____________________________________________________________________

[Final Root Cause]
Security group name is an immutable AWS attribute. Renaming it forces Terraform
to destroy the old SG and create a new one. Terraform default replacement order
is delete-first. AWS blocks deletion because the SG is still attached to the EC2
instance ENI. Terraform gets stuck waiting for a deletion AWS will never allow.

_____________________________________________________________________

[Final Solution]

Manual fix during stuck apply:

  Option 1 — AWS Console:
    EC2 → select instance → Actions → Security → Change Security Groups
    Temporarily assign the default VPC security group.
    Terraform unblocks — old SG deletes, new SG creates, EC2 updated.

  Option 2 — AWS CLI:
    DEFAULT_SG=$(aws ec2 describe-security-groups \
      --filters "Name=vpc-id,Values=<vpc-id>" "Name=group-name,Values=default" \
      --query 'SecurityGroups[0].GroupId' --output text)
    aws ec2 modify-instance-attribute \
      --instance-id i-xxxxxxxxxxxxx \
      --groups $DEFAULT_SG

Prevention for future renames — add lifecycle block before renaming:
  resource "aws_security_group" "wireguard" {
    name = "wireguard-sg-${var.environment}"
    lifecycle {
      create_before_destroy = true
    }
  }

  How create_before_destroy works:
    1. Creates NEW security group first (different name = no conflict)
    2. Updates EC2 to reference new SG
    3. Deletes old SG (now detached, deletion succeeds)

Decision: keep create_before_destroy commented in code — uncomment only when
planning a rename. Rare operation, and leaving it active can cause issues if
new name already exists.

  # Uncomment if planning to rename this SG while attached to EC2.
  # Without this, Terraform tries delete-before-create which fails
  # because the SG is still attached to the instance ENI.
  # lifecycle {
  #   create_before_destroy = true
  # }

Files changed:
  terraform/dev/aws/compute/main.tf   (commented lifecycle block added)
  terraform/prod/aws/compute/main.tf  (same)

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: Temporary assignment to default VPC SG lasts only seconds during apply.
EC2 is updated to correct SG once Terraform completes.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Terraform plan indicators to watch for:

  WARNING — forces replacement (-/+):
    -/+ resource "aws_security_group" "wireguard" {
          ~ name = "old-name" -> "new-name"  # forces replacement
    Action required: review if attached to EC2, consider create_before_destroy.

  SAFE — in-place update (~):
    ~ resource "aws_security_group" "wireguard" {
        ~ tags = { ~ "Name" = "old-tag" -> "new-tag" }
    No attachment concern — not a replacement.

Why create_before_destroy is not enabled by default:
  Rare operation — resources are rarely renamed after creation.
  Risk of naming conflict if new name already exists in AWS.
  Some AWS resources have unique name constraints.
  Prefer explicit intervention for destructive operations.
  Manual awareness = intentional review before rename.