# IAM module for prod environment
# - Creates GitHubActions-Infrastructure-prod role (PowerUserAccess + SecurityBoundary)
# - State stored in prod account S3 bucket under prod/*

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.28.0"
    }
  }

  backend "s3" {
    bucket         = "hybrid-cloud-infrastructure-tf-state-eu"
    key            = "prod/aws/secrets/terraform.tfstate"
    region         = "eu-west-2"
    encrypt        = true
    dynamodb_table = "hybrid-cloud-infrastructure-tf-state-lock-eu"
  }
}

provider "aws" {
  region = "eu-west-2"
}

locals {
  tags = {
    env = "prod"
  }
}
