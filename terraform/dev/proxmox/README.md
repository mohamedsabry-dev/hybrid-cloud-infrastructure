# Dev - Proxmox

Proxmox infrastructure for the dev environment.

## Modules

| Module | Description |
|--------|-------------|
| `resources/` | VMs and infrastructure managed by Terraform |

## Bootstrap

`bootstrap-dev.sh` - Shell script to run on Proxmox server:
- Creates `tf_dev@pve` user
- Assigns Admin role on dev node only (`pve-dev`)
- Generates API token for Terraform

Run this script on the Proxmox host before deploying resources.

## Token Storage

API token stored in AWS Secrets Manager: `dev/proxmox/terraform-token`
