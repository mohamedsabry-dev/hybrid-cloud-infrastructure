terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-west-2"
}

# 1. POSITIVE TEST: Connection Check
# If Terraform can read this, your ACCESS_KEY and SECRET are valid.
data "aws_caller_identity" "current" {}

output "bootstrap_user_arn" {
  value = data.aws_caller_identity.current.arn
}

# List S3 buckets to verify read access
data "aws_s3_buckets" "all" {}
output "s3_bucket_names" {
  value = data.aws_s3_buckets.all.names
}
# List EC2 instances to verify read access
data "aws_instances" "all" {
    filter {
        name   = "instance-state-name"
        values = ["running", "stopped", "pending", "stopping"]
    }
}
output "ec2_instance_ids" {
  value = data.aws_instances.all.ids
}
# List IAM users to verify read access
data "aws_iam_users" "all" {}
output "iam_user_names" {
  value = data.aws_iam_users.all.users[*].user_name
}
# List DynamoDB tables to verify read access
data "aws_dynamodb_tables" "all" {}
output "dynamodb_table_names" {
  value = data.aws_dynamodb_tables.all.names
}
