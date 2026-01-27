# The file is set to ensure you can List S3 bucket objects in the specified bucket.
# Also ensure Backend Setup working (S3 & DynamoDB)

# Get current AWS account info
data "aws_caller_identity" "current" {}

# Get S3 bucket info
data "aws_s3_bucket" "terraform_state" {
  bucket = "hybrid-cloud-infrastructure-terraform-state"
}

# runtf-bootstrap