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
    bucket         = "hybrid-cloud-infrastructure-tf-state-dev-v2"
    key            = "dev/proxmox/vms/jenkins_agents/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "hybrid-cloud-infrastructure-tf-state-lock-dev-v2"
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Environment = "dev"
      ManagedBy   = "terraform"
      Module      = "proxmox-jenkins-agents"
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
