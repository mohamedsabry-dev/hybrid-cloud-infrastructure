terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "6.28.0" }
  }

  backend "s3" {
    bucket         = "hybrid-cloud-infrastructure-terraform-state"
    key            = "app/terraform.tfstate" # Unique Key
    region         = "eu-west-2"
    dynamodb_table = "hybrid-cloud-infrastructure-terraform-state-lock"
    encrypt        = true
  }
}

provider "aws" { region = "eu-west-2" }

# 1. FIND NETWORK RESOURCES (Look up by Tag)
data "aws_subnet" "target_subnet" {
  filter {
    name   = "tag:Name"
    values = ["Hybrid-Cloud-Validation-Subnet"] # Must match Network file
  }
}

# 2. GET LATEST LINUX AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# 3. CREATE INSTANCE (The Permission Test)
resource "aws_instance" "app_test_server" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  subnet_id     = data.aws_subnet.target_subnet.id

  tags = {
    Name        = "App-Role-Validation-Server"
    Environment = "Validation"
  }
}