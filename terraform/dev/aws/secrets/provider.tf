terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.28.0"  # Pinned for offline runner
    }
  }
  
  backend "s3" {
    bucket         = "hybrid-cloud-infrastructure-tf-state-dev"
    key            = "dev/aws/secrets/terraform.tfstate"
    region         = "eu-west-2"
    encrypt        = true
    dynamodb_table = "hybrid-cloud-infrastructure-tf-state-lock-dev"
  }
}

provider "aws" {
  region = "eu-west-2"
  
  default_tags {
    tags = {
      Environment = "dev"
      ManagedBy   = "terraform"
      Module      = "secrets"
    }
  }
}