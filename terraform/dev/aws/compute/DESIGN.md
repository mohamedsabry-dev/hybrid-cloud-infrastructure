# AWS Compute module — design notes

Why the WireGuard EC2 looks the way it does. For the broader VPN
architecture (tunnel IPs, AllowedIPs, keepalive) see
[`../../../../network/vpn/`](../../../../network/vpn/).

---

## Why WireGuard on EC2, not AWS Site-to-Site VPN

AWS Site-to-Site VPN costs ~$36/month per connection (before data transfer)
and provisions two redundant tunnels via a Virtual Private Gateway. For a
home lab with one on-prem endpoint, that's overkill — I don't need
BGP-negotiated failover for a single MikroTik router.

WireGuard on a `t3.micro` costs ~$7.60/month (or less with Reserved
Instance / free-tier). The tradeoff is I manage the VPN myself — key
rotation, keepalive, restart on failure — but the setup is minimal and the
troubleshooting surface is small.

## Why t3.micro

The WireGuard process uses negligible CPU and memory. `t3.micro` (2 vCPU,
1 GB RAM) is more than enough. The instance spends most of its time idle
between tunnel packets. Baseline CPU credit accumulation covers any burst.

I considered `t3.nano` (0.5 GB RAM) but the 1 GB headroom on micro is
useful for debugging tools (tcpdump, ncat) without worrying about OOM. The
cost difference is ~$1.50/month.

## Why source_dest_check = false

By default, AWS drops packets where the EC2 instance isn't the source or
destination (anti-spoofing). The WireGuard EC2 is a router — it forwards
packets between the tunnel and the VPC. Without disabling this check, all
forwarded traffic gets silently dropped.

## Why an Elastic IP instead of the auto-assigned public IP

The on-prem MikroTik needs a stable endpoint to point its WireGuard peer
at. Auto-assigned public IPs change on stop/start. An EIP survives
instance replacement — I can tear down and rebuild the EC2 without
reconfiguring the router.

## Security group scoping

Both ingress rules (UDP 51820 for WireGuard, TCP 22 for SSH) are restricted
to `var.allowed_ip` — my home public IP. This means the WireGuard port
isn't open to the internet, only to the specific IP that should be sending
tunnel traffic. If my ISP changes my IP, I update the variable and re-apply.

Egress is unrestricted (`0.0.0.0/0`). The EC2 needs to reach the internet
for package updates and forward traffic to on-prem subnets through the
tunnel.

## Why user_data only installs packages

The `user_data` script installs WireGuard tools, enables IP forwarding, and
stops. It does NOT generate keys or create the tunnel config. That's done
by `setup-wireguard.sh` (in `network/vpn/`) which runs interactively
because it requires the on-prem router's public key as input.

Splitting setup into two phases — automated package install at provision
time, interactive tunnel config afterward — means `terraform apply` is
fully idempotent and doesn't try to manage WireGuard state.

## The VPC route to on-prem

The `aws_route` resource adds a route for `var.home_cidr` (10.0.0.0/16)
pointing at the WireGuard EC2's network interface. This is what makes
return traffic from AWS reach on-prem subnets — without it, VPC-originated
packets to 10.0.x.x would have no route and get dropped.
