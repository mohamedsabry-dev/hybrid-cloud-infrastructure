# Prod - Secrets Module

Manages AWS Secrets Manager secrets for the prod environment.

## Resources

| Resource | Description |
|----------|-------------|
| `prod/proxmox/terraform-token` | Proxmox API token for tf_prod@pve user |

## Usage

Terraform reads this secret to authenticate with Proxmox API when managing prod infrastructure.

## Secret Format

```json
{
  "token_id": "tf_prod@pve!terraform",
  "token_secret": "<token-value>"
}
```

## Workflow

Deployed by: `.github/workflows/prod-secrets.yml`
