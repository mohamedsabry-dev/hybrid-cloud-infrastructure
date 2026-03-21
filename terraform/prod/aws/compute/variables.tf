variable "allowed_ip" {
  description = "IP address allowed for SSH and WireGuard access (CIDR notation)"
  type        = string
  sensitive   = true
}

variable "vpn_public_key" {
  description = "Public SSH key for VPN EC2 instance"
  type        = string
  sensitive   = true
}

#-------------------------------------------------------------------------------
# Environment Configuration
#-------------------------------------------------------------------------------
variable "environment" {
  description = "Environment name (dev/prod)"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-2"
}

variable "availability_zone" {
  description = "Availability zone for EC2 instance"
  type        = string
  default     = "eu-west-2a"
}

variable "ami_id" {
  description = "AMI ID for WireGuard instance (region-specific)"
  type        = string
  default     = "ami-087c9ba923d9765d8"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "wireguard_port" {
  description = "WireGuard UDP port"
  type        = number
  default     = 51820
}

variable "home_cidr" {
  description = "Home network CIDR for routing"
  type        = string
  default     = "10.0.0.0/16"
}

#-------------------------------------------------------------------------------
# Remote State Configuration
#-------------------------------------------------------------------------------
variable "remote_state_bucket" {
  description = "S3 bucket for remote state"
  type        = string
  default     = "hybrid-cloud-infrastructure-tf-state-prod"
}

variable "remote_state_region" {
  description = "Region for remote state bucket"
  type        = string
  default     = "eu-west-2"
}
