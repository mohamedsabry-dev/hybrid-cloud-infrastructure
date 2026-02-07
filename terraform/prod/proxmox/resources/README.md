# Prod - Proxmox Resources

Manages Proxmox VMs and infrastructure for the prod environment.

## Authentication

- Credentials fetched from AWS Secrets Manager (`prod/proxmox/terraform-token`)
- Uses `tf_prod@pve` user with admin on prod resources

## Current Resources

| Resource | Description |
|----------|-------------|
| `proxmox_virtual_environment_nodes` | Lists all cluster nodes |
| `proxmox_virtual_environment_datastores` | Lists available storage |

## Workflow

Deployed by: `.github/workflows/prod-proxmox-resources.yml`
