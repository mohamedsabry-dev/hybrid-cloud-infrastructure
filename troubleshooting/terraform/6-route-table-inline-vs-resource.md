# TS-TF-006 | 2026-03-14 | RESOLVED

## 1. Context
- System: Terraform with AWS provider
- Environment: AWS VPC with cross-state modules (network + compute)
- Related components: Route tables, aws_route resource, cross-module dependencies

## 2. Issue
- Symptom: Network module tries to remove routes added by compute module. Terraform plan shows route table update removing `10.0.0.0/16` route.
- Error: Happens when running network module after compute module has added routes.

## 3. Analysis

**Check 1: What does the plan show?**

```
# aws_route_table.rt_public will be updated in-place
~ resource "aws_route_table" "rt_public" {
    ~ route = [
        - { cidr_block = "0.0.0.0/0", gateway_id = "igw-xxx" },
        - { cidr_block = "10.0.0.0/16", network_interface_id = "eni-xxx" },  ← REMOVES!
        + { cidr_block = "0.0.0.0/0", gateway_id = "igw-xxx" },
      ]
  }

Plan: 0 to add, 1 to change, 0 to destroy.
```

Finding: Network module sees the compute-added route as "drift" and removes it.

**Check 2: Why is this happening?**

The network module uses **inline routes**:
```hcl
resource "aws_route_table" "rt_public" {
  vpc_id = aws_vpc.vpc_main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw_main.id
  }

  tags = { Name = "dev-public-rt" }
}
```

Finding: Inline `route {}` blocks make Terraform **own ALL routes** in the table. Any route not in the config is seen as drift and removed.

## 4. Root Cause
> `aws_route_table` with inline `route {}` blocks tries to own all routes in the table. It sees routes added by other modules as "drift" and removes them on next apply. This is fundamental Terraform behavior for inline blocks.

## 5. Solution
> Use separate `aws_route` resources instead of inline routes. Each resource owns only its route.

### Approach 1: Inline Routes (PROBLEMATIC)

```hcl
resource "aws_route_table" "rt_public" {
  vpc_id = aws_vpc.vpc_main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw_main.id
  }

  tags = { Name = "dev-public-rt" }
}
```

| Pros | Cons |
|------|------|
| Simple, all-in-one resource | Owns ALL routes in table |
| Easy to read | Conflicts with other modules adding routes |
| | Deletes routes it doesn't know about |
| | Cross-module dependency issues |

### Approach 2: Separate aws_route Resources (RECOMMENDED)

```hcl
resource "aws_route_table" "rt_public" {
  vpc_id = aws_vpc.vpc_main.id
  tags   = { Name = "dev-public-rt" }
  # No inline routes!
}

resource "aws_route" "internet" {
  route_table_id         = aws_route_table.rt_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw_main.id
}
```

**Terraform Plan Output (after compute added 10.0.0.0/16 route):**
```
No changes. Your infrastructure matches the configuration.
```

| Pros | Cons |
|------|------|
| Each module owns only its routes | Slightly more verbose |
| No cross-module conflicts | Route table and route are separate resources |
| Compute can add routes independently | One-time import needed when migrating |
| Clear ownership per route | |
| AWS recommended pattern | |

### Architecture: Cross-State Route Management

```
┌─────────────────────────────────────────────────────────────────┐
│              Network Module (State A)                           │
│  - aws_route_table.rt_public (no inline routes)                 │
│  - aws_route.internet (0.0.0.0/0 → IGW)                         │
│  - outputs: rt_public_id                                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼ data.terraform_remote_state
┌─────────────────────────────────────────────────────────────────┐
│              Compute Module (State B)                           │
│  - aws_instance.wireguard                                       │
│  - aws_route.home_subnets (10.0.0.0/16 → ENI)                   │
└─────────────────────────────────────────────────────────────────┘
```

### Why Compute Creates Routes (Not Network)

```hcl
# In compute/main.tf
resource "aws_route" "home_subnets" {
  route_table_id         = data.terraform_remote_state.network.outputs.rt_public_id
  destination_cidr_block = "10.0.0.0/16"
  network_interface_id   = aws_instance.wireguard.primary_network_interface_id
}
```

**Chicken and egg problem:**
- Route needs `network_interface_id` from EC2 instance
- EC2 instance doesn't exist until compute module runs
- Network module can't reference compute resources (separate state)
- Solution: Compute module creates routes that depend on compute resources

**This is correct because:**
- Each module owns resources it can fully manage
- Network exports `rt_public_id` for other modules to use
- Compute creates `aws_route` resources in the same route table
- No state conflicts - each `aws_route` is independent

### Migration Steps

**One-Time Migration (existing infrastructure):**

Added to workflow with comment to remove after first run:

```yaml
# One-time migration: import route after switching from inline to aws_route resource
# Comment out after first successful run
- name: Import Route (migration)
  run: terraform import aws_route.internet $(terraform output -raw rt_public_id)_0.0.0.0/0 || true
```

**Manual Import (if needed):**
```bash
# Get route table ID
cd terraform/dev/aws/network
terraform output rt_public_id

# Import the route
terraform import aws_route.internet rtb-xxx_0.0.0.0/0
```

**If "RouteAlreadyExists" Error:**
```
Error: creating Route in Route Table (rtb-xxx) with destination (0.0.0.0/0):
RouteAlreadyExists: The route identified by 0.0.0.0/0 already exists
```

Fix: Run import command above, then re-run workflow.

## 6. Solution Risk
- Risk level: LOW
- Potential impact: One-time import required when migrating existing infrastructure

## 7. Impact After Fix
- Observed: Network module no longer removes compute-added routes
- Cross-module route management works correctly
- No state conflicts between modules

## 8. Notes

**Root Cause Summary:**

`aws_route_table` with inline `route {}` blocks:
- Tries to **own all routes** in the table
- Sees routes from other modules as "drift"
- Removes them on next apply

`aws_route` resources:
- Each resource owns **only its route**
- Multiple modules can add routes independently
- No conflicts between states

**Files Changed:**
- `terraform/dev/aws/network/main.tf` - Removed inline route, added `aws_route.internet`
- `terraform/prod/aws/network/main.tf` - Same
- `.github/workflows/dev-aws-network.yml` - Added migration import step
- `.github/workflows/prod-aws-network.yml` - Same

## 9. Workaround (if any)
> If migration not possible: Add `lifecycle { ignore_changes = [route] }` to route table, but this prevents Terraform from managing any routes in that table.
