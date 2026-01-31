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

  # Log all management events (control plane API calls)
  # Includes: CreateSecret, DeleteSecret, UpdateSecret, all IAM/EC2/S3 ops
  # Data events (GetSecretValue) can be added via CloudWatch/EventBridge if needed
  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  # No 'kms_key_id' argument means it uses default S3-managed keys.
}