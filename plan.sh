#!/bin/bash
# plan.sh - Local terraform plan (read-only, no apply)
# Uses the dev-plan IAM user which can only read state and secrets.
set -e

export AWS_PROFILE=dev-plan
MODULE="${1:-.}"

# Fetch Proxmox credentials from Secrets Manager
SECRET=$(aws secretsmanager get-secret-value \
  --secret-id infra/proxmox/api-token \
  --query SecretString --output text 2>/dev/null || true)

if [ -n "$SECRET" ]; then
  export TF_VAR_proxmox_api_token_id=$(echo "$SECRET" | jq -r '.token_id')
  export TF_VAR_proxmox_api_token_secret=$(echo "$SECRET" | jq -r '.token_secret')
fi

cd "$MODULE"
terraform init -input=false
terraform validate
terraform plan
