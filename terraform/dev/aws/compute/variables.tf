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
