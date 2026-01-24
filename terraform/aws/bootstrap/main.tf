terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.28.0"
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

# List S3 buckets to verify read access (using region check as alternative)
data "aws_region" "current" {}
output "aws_region" {
  value = data.aws_region.current.region
}
# List EC2 instances to verify read access (requires ec2:DescribeInstances)
# data "aws_instances" "all" {
#   filter {
#     name   = "instance-state-name"
#     values = ["running", "stopped", "pending", "stopping"]
#   }
# }
# output "ec2_instance_ids" {
#   value = data.aws_instances.all.ids
# }

# List IAM users to verify read access (requires iam:ListUsers on all users)
# data "aws_iam_users" "all" {}
# output "iam_user_names" {
#   value = data.aws_iam_users.all.names
# }

# Test IAM permissions - can only access terraform-network and terraform-application users
# These will fail if users don't exist yet (expected on first run)
data "aws_iam_user" "terraform_network" {
  count     = 0 # Set to 1 after creating terraform-network user
  user_name = "terraform-network"
}

data "aws_iam_user" "terraform_application" {
  count     = 0 # Set to 1 after creating terraform-application user
  user_name = "terraform-application"
}

output "terraform_network_user_arn" {
  value = length(data.aws_iam_user.terraform_network) > 0 ? data.aws_iam_user.terraform_network[0].arn : "user not created yet"
}

output "terraform_application_user_arn" {
  value = length(data.aws_iam_user.terraform_application) > 0 ? data.aws_iam_user.terraform_application[0].arn : "user not created yet"
}
# List DynamoDB tables to verify read access
data "aws_dynamodb_tables" "all" {}
output "dynamodb_table_names" {
  value = data.aws_dynamodb_tables.all.names
}
