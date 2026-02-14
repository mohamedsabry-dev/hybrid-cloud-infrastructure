variable "aws_region" {
  description = "The AWS region to deploy resources in"
  type        = string
}

variable "environment" {
  description = "The environment to deploy resources in"
  type        = string
}

variable "bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  type        = string
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table for state locking"
  type        = string
}

variable "enable_versioning" {
  description = "Enable versioning on S3 bucket"
  type        = bool
  default     = true
}

variable "enable_encryption" {
  description = "Enable encryption on S3 bucket"
  type        = bool
  default     = true
}

variable "tf_state_admin" {
  description = "IAM user for managing Terraform state"
  type        = string
  default     = "terraform_state_admin"
}

variable "console_admin" {
  description = "IAM user for console administration"
  type        = string
  default     = "console_admin"
}