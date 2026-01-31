data "aws_caller_identity" "current" {}

# 1. Reference the Existing Bucket (Created by CloudFormation)
data "aws_s3_bucket" "existing_audit_bucket" {
  bucket = var.audit_bucket
}

# 2. Configure CloudTrail (Standard SSE-S3 Encryption is automatic)
resource "aws_cloudtrail" "main_audit_trail" {
  name                          = var.cloudtrail_name
  s3_bucket_name                = data.aws_s3_bucket.existing_audit_bucket.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  tags = local.tags

  # Management events capture all control plane API calls including:
  # - secretsmanager:CreateSecret, DeleteSecret, UpdateSecret, RotateSecret
  # - All IAM, EC2, S3, etc. operations
  # Data events (GetSecretValue) can be added later via CloudWatch/EventBridge if needed

  # No 'kms_key_id' argument means it uses default S3-managed keys.
}