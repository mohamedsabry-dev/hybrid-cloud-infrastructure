terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.28.0"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.93.1"
    }
    external = {
      source  = "hashicorp/external"
      version = "2.3.4"
    }
  }

  backend "s3" {
    bucket         = "hybrid-cloud-infrastructure-tf-state-dev"
    key            = "dev/proxmox/vms/golden-image/terraform.tfstate"
    region         = "eu-west-2"
    encrypt        = true
    dynamodb_table = "hybrid-cloud-infrastructure-tf-state-lock-dev"
  }
}

provider "aws" {
  region = "eu-west-2"
}

# Fetch Proxmox API credentials from Secrets Manager
data "aws_secretsmanager_secret_version" "proxmox" {
  secret_id = var.proxmox_secret_id
}

# Fetch Proxmox root SSH password from Secrets Manager
data "aws_secretsmanager_secret_version" "proxmox_ssh" {
  secret_id = "dev/proxmox/root-password"
}

locals {
  proxmox_creds = jsondecode(data.aws_secretsmanager_secret_version.proxmox.secret_string)
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${local.proxmox_creds.token_id}=${local.proxmox_creds.token_secret}"
  insecure  = var.proxmox_tls_insecure

  ssh {
    username = "root"
    password = data.aws_secretsmanager_secret_version.proxmox_ssh.secret_string
  }
}

