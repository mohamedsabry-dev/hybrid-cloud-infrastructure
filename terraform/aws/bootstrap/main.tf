## Bootstrap Terraform AWS Provider Configuration and Connection Tests
## Linear Issue: INFRA-291 ##

# Steps: 
# // 1. Decalre AWS Provider Version
# // 2. Configure AWS Provider with Region 
# // 3. Use Data Sources to :
# //    - Check AWS Caller Identity (to verify credentials)
# //    - List S3 Buckets (to verify read access)
# //    - Test IAM Permissions (to verify access to specific users)
# //    - List DynamoDB Tables (to verify read access) 
# //    - List EC2 Instances (to verify no access)
# //    - List IAM Users (to verify no access)
# // 4. Output Results
# // 5. Configure S3 bucket for remote state storage
# // 6. Configure DynamoDB table for state locking
# // 7. Configure the 2 IAM Users
# // 8. Create the Policy Structures 

#### Code ####

# terraform-state-hybrid-cloud-bucket-a0001

## Setup S3 ## 
# 1. Create S3 Bucket for Terraform State
# 2. Enable Versioning
# 3. Enable Server-Side Encryption
# 4. Block Public Access


resource "aws_s3_bucket" "state_bucket" {
  bucket = "hybrid-cloud-terraform-state-bucket-synimp"

  lifecycle {
    prevent_destroy = true
  }

    tags = {
    Name        = "Terraform State Bucket"
    Environment = "production"
    ManagedBy   = "terraform-bootstrap"
    Purpose     = "terraform-state"
    }
}

resource "aws_s3_bucket_versioning" "state_versioning" {
  bucket = aws_s3_bucket.state_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state_encryption" {
  bucket = aws_s3_bucket.state_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state_block_public" {
  bucket = aws_s3_bucket.state_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


## Setup DynamoDB ##
# 1. Create DynamoDB Table for Terraform State Locking
# 2. Set Primary Key
resource "aws_dynamodb_table" "state_lock_table" {
  name         = "terraform-state-lock-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name        = "Terraform State Lock Table"
    Environment = "production"
    ManagedBy   = "terraform-bootstrap"
    Purpose     = "terraform-state-lock"
  }
}

