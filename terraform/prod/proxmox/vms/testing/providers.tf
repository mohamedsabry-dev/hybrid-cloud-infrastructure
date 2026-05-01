terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.28.0"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.96.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "2.3.4"
    }
  }

  backend "s3" {
    bucket         = "hybrid-cloud-infrastructure-tf-state-prod"
    key            = "prod/proxmox/vms/test/terraform.tfstate"
    region         = "eu-west-2"
    encrypt        = true
    dynamodb_table = "hybrid-cloud-infrastructure-tf-state-lock-prod"
  }
}

provider "aws" {
  region = "eu-west-2"

  default_tags {
    tags = {
      Environment = "prod"
      ManagedBy   = "terraform"
      Module      = "proxmox-testing-vms"
    }
  }
}

#===============================================================================
# Proxmox Provider
#===============================================================================

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_tls_insecure
}
