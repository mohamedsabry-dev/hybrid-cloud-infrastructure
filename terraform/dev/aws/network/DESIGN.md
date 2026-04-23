# AWS Network module — design notes

Why the VPC layout looks the way it does.

---

## VPC CIDR scheme

Each environment gets a /16 VPC CIDR that mirrors the WireGuard tunnel
address space:

- Dev:  `172.16.0.0/16`
- Prod: `172.17.0.0/16`

This isn't arbitrary — the WireGuard tunnel IPs sit inside the VPC range
(e.g., dev tunnel is `172.16.200.2/16`). That simplifies on-prem routing:
a single AllowedIPs entry on the MikroTik covers both tunnel and VPC
subnets. No need for separate routes for tunnel vs. cloud traffic.

The /16 is much larger than what I currently use, but it costs nothing and
avoids re-addressing if I add subnets later.

## Why two subnets, not one

- **VPN subnet** (`172.16.55.0/24`): public-facing, hosts the WireGuard
  EC2. Associated with the public route table (internet gateway route).
- **Management subnet** (`172.16.53.0/24`): reserved for internal services
  that don't need direct internet access. Not currently used but in place
  so I don't have to restructure the VPC when I need it.

Both subnets are in the same AZ. Multi-AZ would add NAT Gateway costs
($32/month per AZ) for no benefit — this environment has one EC2 instance
and no high-availability requirement on the AWS side.

## Why Route53 private zone

The `lab.local` private hosted zone lets AWS-side services resolve
on-prem-style hostnames. The `for_each` block creates A records for
services (nginx, prometheus, grafana, etc.) pointing at `var.dns_ingress_ip`
— the on-prem ingress point.

This means if I later run workloads in AWS that need to call on-prem
services, DNS resolution works without hardcoding IPs. It also keeps the
naming consistent: `nginx-dev.lab.local` resolves whether you're on-prem
or in the VPC.

## Why both subnets use the public route table

The management subnet is on the public route table even though it's
"internal." Without a NAT Gateway, putting it on a private route table
would mean no internet access at all — not even for package updates. Since
there are no instances in it yet, the security posture is the same. If I
add instances later and want true isolation, I'll add a NAT Gateway and a
private route table at that point.
