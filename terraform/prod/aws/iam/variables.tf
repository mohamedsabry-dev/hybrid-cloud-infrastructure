# Input variables

variable "environment" {
  description = "Environment name (dev/prod)"
  type        = string
  default     = "prod"
}

variable "github_repo" {
  description = "GitHub repository in format owner/repo"
  type        = string
  default     = "mohamedsabry-dev/hybrid-cloud-infrastructure"
}

variable "state_bucket_name" {
  description = "S3 bucket name for Terraform state"
  type        = string
  default     = "hybrid-cloud-infrastructure-tf-state-prod"
}

variable "lock_table_name" {
  description = "DynamoDB table name for state locking"
  type        = string
  default     = "hybrid-cloud-infrastructure-tf-state-lock-prod"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-2"
}

variable "account_id" {
  description = "AWS Account ID"
  type        = string
  sensitive   = true
}
