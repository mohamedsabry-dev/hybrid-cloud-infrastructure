# 1. Define the Terraform Provider requirements
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# 2. Configure the AWS Provider
# Terraform will automatically look for credentials in your ~/.aws/credentials 
# or GITHUB_ACTIONS secrets.
provider "aws" {
  region = "eu-west-2"
}

# 3. Use a Data Source to fetch your current identity
data "aws_caller_identity" "current" {}

# 4. Output the results so we can see them in the terminal/GitHub logs
output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "aws_user_arn" {
  value = data.aws_caller_identity.current.arn
}