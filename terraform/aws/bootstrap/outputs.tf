## Outputs for AWS Bootstrap Module
# // 1. AWS Caller Identity
# // 2. List S3 Buckets
# // 3. List IAM Users Permissions
# // 4. List DynamoDB Tables
# // 5. Current AWS Region

#### Code ####
  output "bootstrap_user_arn" {
    value = data.aws_caller_identity.current.arn
  }

  output "s3_bucket_arn" {
    value = length(data.aws_s3_bucket.terraform_state) > 0 ? data.aws_s3_bucket.terraform_state[0].arn : "bucket not created yet"
  }

  output "terraform_users_arns" {
    value = {
      network     = length(data.aws_iam_user.terraform_network) > 0 ? data.aws_iam_user.terraform_network[0].arn : "user not created yet"
      application = length(data.aws_iam_user.terraform_application) > 0 ? data.aws_iam_user.terraform_application[0].arn : "user not created yet"
    }
  }

  output "dynamodb_table_names" {
    value = data.aws_dynamodb_tables.all.names
  }

  output "aws_region" {
    value = data.aws_region.current.region
  }

  output "ec2_instance_ids" {
    value = length(data.aws_instances.all) > 0 ? data.aws_instances.all[0].ids : "no permissions to list EC2 instances"
  }

  output "iam_user_names" {
    value = length(data.aws_iam_users.all) > 0 ? data.aws_iam_users.all[0].names : "no permissions to list IAM users"
  }