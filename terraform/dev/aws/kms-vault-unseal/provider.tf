terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.28.0"  # Pinned for offline runner
    }
  }
  
  backend "s3" {
    bucket         = "hybrid-cloud-infrastructure-tf-state-dev-v2"
    key            = "dev/aws/kms-vault-unseal/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "hybrid-cloud-infrastructure-tf-state-lock-dev-v2"
  }
}

provider "aws" {
  region = "us-east-1"
  
  default_tags {
    tags = {
      Environment = "dev"
      ManagedBy   = "terraform"
      Module      = "kms-vault-unseal"
    }
  }
}