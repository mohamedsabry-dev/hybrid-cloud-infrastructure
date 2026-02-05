# Terraform creates the secret container (IaC)
# Secret VALUE is injected manually via CLI (never in code or state)
#
# After terraform apply, inject the value once:
#   aws secretsmanager put-secret-value \
#     --secret-id infra/proxmox/api-token \
#     --secret-string '{"token_id":"terraform@pve!terraform-token","token_secret":"<SECRET>"}'

resource "aws_secretsmanager_secret" "proxmox_api_token" {
  name        = "infra/proxmox/api-token"
  description = "Proxmox API token for Terraform provider"

  tags = local.tags
}
