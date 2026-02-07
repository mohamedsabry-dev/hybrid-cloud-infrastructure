# Dev - Secrets Module

Manages AWS Secrets Manager secrets for the dev environment.

## Resources

| Resource | Description |
|----------|-------------|
| `dev/proxmox/terraform-token` | Proxmox API token for tf_dev@pve user |

## Usage

Terraform reads this secret to authenticate with Proxmox API when managing dev infrastructure.

## Secret Format

```json
{
  "token_id": "tf_dev@pve!terraform",
  "token_secret": "<token-value>"
}
```

## Workflow

Deployed by: `.github/workflows/dev-secrets.yml`
