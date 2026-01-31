variable "audit_bucket" {
  type        = string
  default     = "hybrid-cloud-infrastructure-audit-logs"
  description = "The name of the existing S3 bucket for audit logs"
}

variable "cloudtrail_name" {
  type        = string
  default     = "hybrid-main-trail"
  description = "The name of the CloudTrail trail"
}