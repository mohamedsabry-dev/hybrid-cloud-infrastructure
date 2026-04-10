# TS-TF-007 | 2026-03-21 | RESOLVED

## 1. Context
- System: Terraform with AWS provider
- Environment: AWS EC2
- Related components: Security groups, ENI (network interface), EC2 instances

## 2. Issue
- Symptom: `terraform apply` stuck on "Still destroying..." for security group, takes 2+ minutes without progress, eventually times out or fails
- Error:
```
aws_security_group.wireguard: Still destroying... [id=sg-07d51802e9ca80234, 01m30s elapsed]
aws_security_group.wireguard: Still destroying... [id=sg-07d51802e9ca80234, 01m40s elapsed]
aws_security_group.wireguard: Still destroying... [id=sg-07d51802e9ca80234, 01m50s elapsed]
```

## 3. Analysis

**Check 1: What operation is Terraform attempting?**

Terraform plan shows `-/+` (destroy and create replacement):
```
-/+ resource "aws_security_group" "wireguard" {
      ~ name = "dev-wireguard-sg" -> "wireguard-sg-dev" # forces replacement
```

Finding: Security group name is immutable - changing it forces replacement.

**Check 2: Why is deletion stuck?**

AWS restriction: Cannot delete a security group that is attached to an ENI (network interface).

**The conflict:**
1. Terraform tries to delete old SG first (default behavior)
2. EC2 instance still references the old SG via its ENI
3. AWS refuses deletion → Terraform stuck waiting

## 4. Root Cause
> When a security group name changes (immutable attribute), Terraform plans "destroy and then create replacement" (`-/+`). However, AWS cannot delete a security group that is attached to an ENI. The EC2 instance still references the old SG, causing Terraform to get stuck waiting for deletion that can never succeed.

## 5. Solution
> Manually detach SG during stuck apply, or use `create_before_destroy` lifecycle for future renames.

### Manual Fix (During Stuck Apply)

While Terraform is stuck destroying:

**Option 1: AWS Console**
1. Go to EC2 → Select the instance
2. Actions → Security → Change Security Groups
3. Temporarily assign the **default VPC security group**
4. Terraform will complete (old SG deletes, new SG creates)

**Option 2: AWS CLI**
```bash
# Get default SG for the VPC
DEFAULT_SG=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=<vpc-id>" "Name=group-name,Values=default" \
  --query 'SecurityGroups[0].GroupId' --output text)

# Temporarily assign default SG
aws ec2 modify-instance-attribute \
  --instance-id i-xxxxxxxxxxxxx \
  --groups $DEFAULT_SG
```

After running either option, Terraform continues and:
- Deletes old security group
- Creates new security group with new name
- Updates EC2 to use new security group (replaces default SG)

### Prevention: create_before_destroy

Add lifecycle rule **before** renaming:

```hcl
resource "aws_security_group" "wireguard" {
  name = "wireguard-sg-${var.environment}"
  # ...

  lifecycle {
    create_before_destroy = true
  }
}
```

**How it works:**
1. Creates NEW security group first (different name, so no conflict)
2. Updates EC2 to reference new SG
3. Deletes old SG (now detached, deletion succeeds)

## 6. Solution Risk
- Risk level: LOW
- Potential impact: Temporary assignment to default SG during apply (seconds)

## 7. Impact After Fix
- Observed: Terraform apply completes successfully
- Security group renamed without stuck state
- EC2 instance uses new security group

## 8. Notes

### Why We Don't Enable create_before_destroy by Default

| Reason | Explanation |
|--------|-------------|
| Rare operation | Resources are rarely renamed after creation |
| Naming conflicts | If new name already exists, create-before-destroy fails |
| Manual awareness | Prefer explicit intervention for destructive operations |
| AWS naming | Some AWS resources have unique name constraints |

**Our approach:** Keep `create_before_destroy` commented in code. Uncomment only when planning a rename operation.

```hcl
# Uncomment if planning to rename this SG while attached to EC2.
# Without this, Terraform tries delete-before-create which fails
# because the SG is still attached to the instance ENI.
# lifecycle {
#   create_before_destroy = true
# }
```

### Terraform Plan Indicators

**Warning sign - look for `-/+` with "forces replacement":**
```
-/+ resource "aws_security_group" "wireguard" {
      ~ name = "old-name" -> "new-name" # forces replacement
```

**Safe - update in-place (`~`):**
```
~ resource "aws_security_group" "wireguard" {
    ~ tags = {
        ~ "Name" = "old-tag" -> "new-tag"
      }
```

### Files Changed

- `terraform/dev/aws/compute/main.tf` - Added commented lifecycle block
- `terraform/prod/aws/compute/main.tf` - Same
- `terraform/dev/aws/compute/README.md` - Added troubleshooting section
- `terraform/prod/aws/compute/README.md` - Same

## 9. Workaround (if any)
> If stuck mid-apply: Manually assign default VPC security group to the instance via AWS Console or CLI, then Terraform will complete.
