terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.93.1"
    }
  }

  backend "s3" {
    bucket         = "hybrid-cloud-infrastructure-terraform-state"
    key            = "proxmox/prod/terraform.tfstate"
    region         = "eu-west-2"
    encrypt        = true
    dynamodb_table = "hybrid-cloud-infrastructure-terraform-state-lock"
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = true # self-signed cert

  ssh {
    agent = false
  }
}
