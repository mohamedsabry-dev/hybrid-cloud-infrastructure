terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.28.0"
    }
  }

  backend "s3" {
    bucket         = "hybrid-cloud-infrastructure-terraform-state"
    key            = "network/terraform.tfstate" # ⚠️ CHANGED from 'bootstrap' to 'network'
    region         = "eu-west-2"
    dynamodb_table = "hybrid-cloud-infrastructure-terraform-state-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = "eu-west-2"
}

# 1. VPC
resource "aws_vpc" "test_validation_vpc" {
  cidr_block = "10.100.0.0/16"
  
  tags = {
    Name        = "Hybrid-Cloud-Validation-Test"
    Environment = "Validation"
    ManagedBy   = "Terraform"
  }
}

# 2. SUBNET (Needed for EC2 Test later)
resource "aws_subnet" "test_validation_subnet" {
  vpc_id     = aws_vpc.test_validation_vpc.id
  cidr_block = "10.100.1.0/24"

  tags = {
    Name        = "Hybrid-Cloud-Validation-Subnet"
    Environment = "Validation"
  }
}

# 3. OUTPUTS (To help us debug)
output "vpc_id" {
  value = aws_vpc.test_validation_vpc.id
}

output "subnet_id" {
  value = aws_subnet.test_validation_subnet.id
}