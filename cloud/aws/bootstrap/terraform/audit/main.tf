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

  # advanced_event_selector is required for Secrets Manager data events
  # (event_selector only supports S3, DynamoDB, Lambda)
  advanced_event_selector {
    name = "Log management events"

    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
  }

  advanced_event_selector {
    name = "Log Secrets Manager data events"

    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }

    field_selector {
      field  = "resources.type"
      equals = ["AWS::SecretsManager::Secret"]
    }
  }

  # No 'kms_key_id' argument means it uses default S3-managed keys.
}