# TS-TF-006 | 2026-03-14 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Terraform / AWS
Sub-techs: Terraform AWS provider, aws_route_table, aws_route, cross-state modules,
           route table ownership, remote state
Environment: AWS VPC | cross-state modules (network + compute)
Re-opened: No

_____________________________________________________________________

[Issue Description]
Network module tries to remove routes added by compute module. Every time the
network module runs after compute has added routes, Terraform plans to delete
the compute-added routes.

  aws_route_table.rt_public will be updated in-place:
  ~ route = [
      - { cidr_block = "0.0.0.0/0", gateway_id = "igw-xxx" }
      - { cidr_block = "10.0.0.0/16", network_interface_id = "eni-xxx" }  ← REMOVES!
      + { cidr_block = "0.0.0.0/0", gateway_id = "igw-xxx" }
    ]

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Checked what in the network module config was causing it to own all routes.

Network module was using inline route {} blocks:
  resource "aws_route_table" "rt_public" {
    vpc_id = aws_vpc.vpc_main.id
    route {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.igw_main.id
    }
    tags = { Name = "dev-public-rt" }
  }

Inline route {} blocks cause aws_route_table to own ALL routes in the table.
Any route not explicitly listed in the config is seen as drift and removed on
next apply. The 10.0.0.0/16 route added by the compute module was not in the
network module config — so Terraform removed it.


# Suspected Root Cause
aws_route_table with inline route {} blocks tries to own all routes in the
table. Routes added by other modules are treated as drift and removed.
This is fundamental Terraform behaviour for inline blocks — not a bug.


# More Checks Notes:
Why compute module adds routes instead of network module:
  The 10.0.0.0/16 route needs network_interface_id from the WireGuard EC2 instance.
  EC2 instance does not exist until compute module runs.
  Network module runs separately (different state) and cannot reference compute
  resources. Compute module must own the routes that depend on compute resources.

  Cross-state architecture:
    Network module (State A):
      aws_route_table.rt_public (no inline routes)
      aws_route.internet (0.0.0.0/0 → IGW)
      output: rt_public_id

    Compute module (State B):
      aws_instance.wireguard
      aws_route.home_subnets (10.0.0.0/16 → ENI)
      reads rt_public_id via data.terraform_remote_state


# Suspected Solution
Replace inline route {} blocks with separate aws_route resources.
Each aws_route resource owns only its specific route — no ownership conflict.


# Test
Replaced inline route with aws_route.internet, re-ran network module after
compute module had added the 10.0.0.0/16 route.

Result: PASS
  Terraform plan output: No changes. Your infrastructure matches the configuration.
  Network module no longer sees compute-added route as drift.

_____________________________________________________________________

[Final Root Cause]
aws_route_table with inline route {} blocks claims ownership of all routes in
the table — any route not in the config is removed on next apply. The compute
module added a 10.0.0.0/16 route to the same table. Network module did not
know about it and removed it on every subsequent run.

_____________________________________________________________________

[Final Solution]
Removed inline route {} blocks from aws_route_table. Created separate
aws_route resource for each route. Each resource owns only its own route —
multiple modules can safely add routes to the same table.

  Before (PROBLEMATIC — inline routes, owns everything):
    resource "aws_route_table" "rt_public" {
      vpc_id = aws_vpc.vpc_main.id
      route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw_main.id
      }
    }

  After (CORRECT — separate resource, owns only this route):
    resource "aws_route_table" "rt_public" {
      vpc_id = aws_vpc.vpc_main.id
      tags   = { Name = "dev-public-rt" }
      # no inline routes
    }

    resource "aws_route" "internet" {
      route_table_id         = aws_route_table.rt_public.id
      destination_cidr_block = "0.0.0.0/0"
      gateway_id             = aws_internet_gateway.igw_main.id
    }

  Compute module (unchanged — already correct pattern):
    resource "aws_route" "home_subnets" {
      route_table_id         = data.terraform_remote_state.network.outputs.rt_public_id
      destination_cidr_block = "10.0.0.0/16"
      network_interface_id   = aws_instance.wireguard.primary_network_interface_id
    }

One-time migration — import existing route after switching from inline to aws_route:
  terraform import aws_route.internet rtb-xxx_0.0.0.0/0

  If RouteAlreadyExists error on first apply after import:
    Error: creating Route in Route Table (rtb-xxx): RouteAlreadyExists: 0.0.0.0/0
    Fix: run the import command above, then re-run.

  Added to workflow with comment to remove after first successful run:
    terraform import aws_route.internet $(terraform output -raw rt_public_id)_0.0.0.0/0 || true

Files changed:
  terraform/dev/aws/network/main.tf
  terraform/prod/aws/network/main.tf
  .github/workflows/dev-aws-network.yml  (migration import step)
  .github/workflows/prod-aws-network.yml (migration import step)

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: One-time import required when migrating existing infrastructure.
No functional impact after migration.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

aws_route_table inline route {} vs aws_route resource:

  Inline route {}:
    Pros: simple, all-in-one, easy to read
    Cons: owns ALL routes in table, conflicts with other modules,
          deletes routes it does not know about

  Separate aws_route resources:
    Pros: each module owns only its routes, no cross-module conflicts,
          compute can add routes independently, AWS recommended pattern
    Cons: slightly more verbose, one-time import when migrating

The core principle: in Terraform, inline blocks mean "I own everything in this
collection." Separate resources mean "I own only this one item." When multiple
modules share the same AWS resource (like a route table), always use separate
resource types rather than inline blocks.

Workaround if migration not possible:
  lifecycle { ignore_changes = [route] }
  Warning: this prevents Terraform from managing ANY routes in that table.