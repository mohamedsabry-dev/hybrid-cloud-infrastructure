output "cloudtrail_name" {
  description = "The name of the CloudTrail trail"
  value       = aws_cloudtrail.main_audit_trail.name
}

output "cloudtrail_id" {
  description = "The ID of the CloudTrail trail"
  value       = aws_cloudtrail.main_audit_trail.id
}

output "cloudtrail_arn" {
  description = "The ARN of the CloudTrail trail"
  value       = aws_cloudtrail.main_audit_trail.arn
}

output "s3_bucket_name" {
  description = "The S3 bucket name for audit logs"
  value       = data.aws_s3_bucket.existing_audit_bucket.id
}

output "s3_bucket_arn" {
  description = "The ARN of the S3 bucket for audit logs"
  value       = data.aws_s3_bucket.existing_audit_bucket.arn
}

output "aws_account_id" {
  description = "The AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "is_multi_region_trail" {
  description = "Whether the trail is multi-region"
  value       = aws_cloudtrail.main_audit_trail.is_multi_region_trail
}

output "cloudtrail_enabled" {
  description = "Whether CloudTrail log file validation is enabled"
  value       = aws_cloudtrail.main_audit_trail.enable_log_file_validation
}
