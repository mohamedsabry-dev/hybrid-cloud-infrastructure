# File: terraform/aws/test/provider.tf

terraform {
  required_version = ">= 1.1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version =  "6.28.0"
    }
  }

  # Configure S3 backend for state storage
  backend "s3" {
    bucket         = "hybrid-cloud-infrastructure-terraform-state"
    key            = "bootstrap/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "hybrid-cloud-infrastructure-terraform-state-lock"
    encrypt        = true
  }
}

  provider "aws" {
    region = "eu-west-2"
  }