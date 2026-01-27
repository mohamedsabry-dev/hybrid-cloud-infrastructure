# File: terraform/aws/test/main.tf

# Get current AWS account info
data "aws_caller_identity" "current" {}

# Get S3 bucket info
data "aws_s3_bucket" "terraform_state" {
  bucket = "hybrid-cloud-infrastructure-terraform-state"
}

# Get DynamoDB table info
data "aws_dynamodb_table" "state_lock" {
  name = "hybrid-cloud-infrastructure-terraform-state-lock"
}