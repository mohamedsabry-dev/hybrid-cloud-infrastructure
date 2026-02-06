

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
    key            = "dev/terraform.tfstate"
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
    env = "dev"
  }
}