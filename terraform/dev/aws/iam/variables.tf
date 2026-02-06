# Input variables

variable "prod_account_id" {
  description = "Prod AWS Account ID (where state bucket and lock table live)"
  type        = string
  default     = "969041180300"
}

variable "github_repo" {
  description = "GitHub repository in format owner/repo"
  type        = string
  default     = "mohamedsabry-dev/hybrid-cloud-infrastructure"
}

variable "state_bucket_name" {
  description = "S3 bucket name for Terraform state"
  type        = string
  default     = "hybrid-cloud-infrastructure-tf-state-eu"
}

variable "lock_table_name" {
  description = "DynamoDB table name for state locking"
  type        = string
  default     = "hybrid-cloud-infrastructure-tf-state-lock-eu"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-2"
}
