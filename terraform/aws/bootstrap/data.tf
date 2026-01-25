## Retrieve information from AWS for: 
# // 1. AWS Caller Identity
# // 2. List S3 Buckets
# // 3. List IAM Users Permissions
# // 4. List DynamoDB Tables
# // 5. Current AWS Region
# // 6. Failures expected EC2 Instances (no permissions)
# // 7. Failures expected IAM Users (no permissions)


#### Code ####

  data "aws_caller_identity" "current" {
  }
  data "aws_s3_bucket" "terraform_state" {
    count  = 0 # Set to 1 after creating the bucket
    bucket = "hybrid-cloud-terraform-state-bucket-synimp"
  }
  data "aws_iam_user" "terraform_network" {
    count     = 0 # Set to 1 after creating terraform-network user
    user_name = "terraform-network"
  }
  data "aws_iam_user" "terraform_application" {
    count     = 0 # Set to 1 after creating terraform-application user
    user_name = "terraform-application"
  }
  data "aws_dynamodb_tables" "all" {
  }
  data "aws_region" "current" {
  }
  data "aws_instances" "all" {
    count = 0 # No permissions expected, set to 1 if permissions are granted
    filter {
      name   = "instance-state-name"
      values = ["running", "stopped", "pending", "stopping"]
    }
  }
  data "aws_iam_users" "all" {
    count = 0 # No permissions expected, set to 1 if permissions are granted
  }