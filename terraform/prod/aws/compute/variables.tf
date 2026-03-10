variable "allowed_ip" {
  description = "IP address allowed for SSH and WireGuard access (CIDR notation)"
  type        = string
  sensitive   = true
}
