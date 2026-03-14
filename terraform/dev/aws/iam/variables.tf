# Input variables

variable "github_repo" {
  description = "GitHub repository in format owner/repo"
  type        = string
  default     = "mohamedsabry-dev/hybrid-cloud-infrastructure"
}

variable "state_bucket_name" {
  description = "S3 bucket name for Terraform state"
  type        = string
  default     = "hybrid-cloud-infrastructure-tf-state-dev-v2"
}

variable "lock_table_name" {
  description = "DynamoDB table name for state locking"
  type        = string
  default     = "hybrid-cloud-infrastructure-tf-state-lock-dev-v2"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "dev_account_id" {
  description = "Dev AWS Account ID"
  type        = string
  default     = "637423413657"
}
