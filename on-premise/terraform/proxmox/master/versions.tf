terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "= 0.93.0"
    }
  }

  # Remote state stored in S3 with DynamoDB locking
  # Uncomment when ready to use remote state
  # backend "s3" {
  #   bucket         = "hybrid-cloud-dev-terraform-state"
  #   key            = "on-premise/proxmox/master/terraform.tfstate"
  #   region         = "eu-west-2"
  #   dynamodb_table = "terraform-state-lock-dev"
  #   encrypt        = true
  # }
}
