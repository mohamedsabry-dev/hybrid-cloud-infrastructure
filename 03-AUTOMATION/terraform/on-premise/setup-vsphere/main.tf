terraform {
  required_version = ">= 1.0.0"

  required_providers {
    vsphere = {
      source  = "hashicorp/vsphere"
      version = "~> 2.12"
    }
  }

  # Remote state stored in S3 with DynamoDB locking
  # AWS credentials from GitHub Secrets: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
  backend "s3" {
    bucket         = "hybrid-cloud-dev-terraform-state"
    key            = "on-premise/setup-vsphere/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "terraform-state-lock-dev"
    encrypt        = true
  }
}

# vSphere Provider - credentials from GitHub Secrets:
# TF_VAR_vsphere_user, TF_VAR_vsphere_password, TF_VAR_vsphere_server
provider "vsphere" {
  user                 = var.vsphere_user
  password             = var.vsphere_password
  vsphere_server       = var.vsphere_server
  allow_unverified_ssl = var.vsphere_allow_unverified_ssl
}
