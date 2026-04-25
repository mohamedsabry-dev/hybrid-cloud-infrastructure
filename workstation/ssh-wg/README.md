# SSH Config — VPN + GitHub

SSH config template for the Mac Mini to reach the WireGuard VPN endpoints
(dev + prod) and to bypass firewall restrictions on GitHub SSH by using
port 443 instead of the default 22.

## Files

| File | Description |
|------|-------------|
| `ssh-config-template` | SSH config entries for `wg-dev`, `wg-prod`, and `github.com` via port 443 |

## Hosts defined in the template

| Host | Purpose |
|------|---------|
| `wg-dev` | WireGuard VPN endpoint for the dev AWS account (Elastic IP placeholder) |
| `wg-prod` | WireGuard VPN endpoint for the prod AWS account (Elastic IP placeholder) |
| `github.com` | GitHub via `ssh.github.com:443` — works on networks that block outbound 22 |

## Usage

Append the template to `~/.ssh/config` and substitute the `<DEV_EIP>` /
`<PROD_EIP>` placeholders with the real Elastic IPs (pulled from Terraform
output or the AWS console). The two `.pem` key files are expected at
`~/WorkSpace/vpn-key-pair-dev.pem` and `~/WorkSpace/vpn-key-pair-prod.pem`.

## Related

- [`../README.md`](../README.md) — workstation scope
- [`../../deployment-docs/05-vpn-setup-guide.md`](../../deployment-docs/05-vpn-setup-guide.md) — WireGuard VPN setup end-to-end
