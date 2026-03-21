# Input variables

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
  description = "Availability zone for subnets"
  type        = string
  default     = "eu-west-2a"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "172.17.0.0/16"
}

variable "subnet_vpn_cidr" {
  description = "CIDR block for VPN subnet"
  type        = string
  default     = "172.17.65.0/24"
}

variable "subnet_mgmt_cidr" {
  description = "CIDR block for management subnet"
  type        = string
  default     = "172.17.63.0/24"
}
