terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # PHASE 2: Uncomment the backend block below AFTER the S3 bucket and DynamoDB table are created
  # Then run: terraform init -migrate-state -force-copy
  #
  # backend "s3" {
  #   bucket         = "hybrid-cloud-dev-terraform-state"   # or hybrid-cloud-prod-terraform-state
  #   key            = "pre-flight/terraform.tfstate"
  #   region         = "eu-west-2"
  #   dynamodb_table = "terraform-state-lock-dev"          # or terraform-state-lock-prod
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Hybrid-Cloud-Infrastructure"
      ManagedBy   = "Terraform"
      Environment = var.environment
    }
  }
}
