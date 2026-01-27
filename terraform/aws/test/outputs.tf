# File: terraform/aws/test/outputs.tf

output "account_id" {
  description = "Current AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "s3_bucket_arn" {
  description = "Terraform state bucket ARN"
  value       = data.aws_s3_bucket.terraform_state.arn
}

output "s3_bucket_versioning" {
  description = "S3 bucket versioning status"
  value       = data.aws_s3_bucket.terraform_state.versioning[0].enabled
}

output "dynamodb_table_arn" {
  description = "State lock table ARN"
  value       = data.aws_dynamodb_table.state_lock.arn
}

output "dynamodb_billing_mode" {
  description = "DynamoDB billing mode"
  value       = data.aws_dynamodb_table.state_lock.billing_mode
}