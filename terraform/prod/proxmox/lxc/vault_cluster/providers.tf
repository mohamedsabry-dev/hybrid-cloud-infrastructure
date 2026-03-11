terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.28.0"  # Pinned for offline runner
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.96.0"  # Fixed mount_point bug (issue #2507)
    }
    external = {
      source  = "hashicorp/external"
      version = "2.3.4"  # Pinned for offline runner
    }
  }

  backend "s3" {
    bucket         = "hybrid-cloud-infrastructure-tf-state-prod"
    key            = "prod/proxmox/lxc/vault_cluster/terraform.tfstate"
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
      Module      = "proxmox-vault-cluster-lxc"
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
