terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "hybrid-cloud-dev-terraform-state"
    key            = "pre-flight/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "terraform-state-lock-dev"
    encrypt        = true
  }
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
