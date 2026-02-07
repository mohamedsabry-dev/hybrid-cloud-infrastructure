# Prod - Proxmox

Proxmox infrastructure for the prod environment.

## Modules

| Module | Description |
|--------|-------------|
| `resources/` | VMs and infrastructure managed by Terraform |

## Bootstrap

`bootstrap-prod.sh` - Shell script to run on Proxmox server:
- Creates `tf_prod@pve` user
- Assigns Admin role on prod resources
- Generates API token for Terraform

Run this script on the Proxmox host before deploying resources.

## Token Storage

API token stored in AWS Secrets Manager: `prod/proxmox/terraform-token`
