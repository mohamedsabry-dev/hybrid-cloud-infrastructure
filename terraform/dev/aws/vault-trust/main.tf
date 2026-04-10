# Vault Trust - AWS Resources for Vault AWS Secrets Engine
# =========================================================
#
# This module creates AWS resources needed for Vault to generate
# temporary AWS credentials for etcd backup to S3.
#
# Resources:
#   - iam.tf:     IAM user, access key, roles, policies
#   - secrets.tf: Secrets Manager for storing IAM credentials
#   - s3.tf:      S3 bucket for etcd backups
#
# Flow:
#   K8s Pod → Vault (K8s Auth) → AWS STS (AssumeRole) → S3 Bucket
