terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "6.28.0" }
  }

  backend "s3" {
    bucket         = "hybrid-cloud-infrastructure-terraform-state"
    key            = "audit/terraform.tfstate" # Unique Key
    region         = "eu-west-2"
    dynamodb_table = "hybrid-cloud-infrastructure-terraform-state-lock"
    encrypt        = true
  }
}

provider "aws" { region = "eu-west-2" }

# 1. TEST READ ACCESS (VPC)
data "aws_vpc" "audit_vpc" {
  filter {
    name   = "tag:Environment"
    values = ["Validation"]
  }
}

# 2. TEST READ ACCESS (Instance)
data "aws_instance" "audit_app" {
  filter {
    name   = "tag:Name"
    values = ["App-Role-Validation-Server"]
  }
  depends_on = [ data.aws_vpc.audit_vpc ]
}

# 3. REPORT FINDINGS
output "audit_status" {
  value = "SUCCESS: Found VPC ${data.aws_vpc.audit_vpc.id} and Server ${data.aws_instance.audit_app.id}"
}