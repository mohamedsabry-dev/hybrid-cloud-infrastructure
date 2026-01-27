# File: terraform/aws/test/outputs.tf

output "account_id" {
  description = "Current AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "assumed_role_arn" {
  description = "ARN of the role assumed by GitHub Actions"
  value       = data.aws_caller_identity.current.arn
}

output "s3_bucket_name" {
  description = "Terraform state bucket name"
  value       = data.aws_s3_bucket.terraform_state.bucket
}

output "s3_bucket_arn" {
  description = "Terraform state bucket ARN"
  value       = data.aws_s3_bucket.terraform_state.arn
}

output "s3_bucket_region" {
  description = "S3 bucket region"
  value       = data.aws_s3_bucket.terraform_state.region
}
