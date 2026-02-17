terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.28.0"  # Pinned for offline runner
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.93.1"  # Pinned for offline runner
    }
    external = {
      source  = "hashicorp/external"
      version = "2.3.4"  # Pinned for offline runner
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
  
  default_tags {
    tags = {
      Environment = "dev"
      ManagedBy   = "terraform"
      Module      = "proxmox-golden-image"
    }
  }
}


provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_tls_insecure

  ssh {
    username = var.proxmox_ssh_username
    password = var.proxmox_ssh_password
  }
}