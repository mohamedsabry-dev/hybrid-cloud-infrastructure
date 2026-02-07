variable "proxmox_api_url" {
  description = "Proxmox API URL (base URL without /api2/json)"
  type        = string
  default     = "https://pve-dev:8006"
}

variable "proxmox_tls_insecure" {
  description = "Skip TLS verification (set false in production with valid certs)"
  type        = bool
  default     = true
}

variable "proxmox_secret_id" {
  description = "Secrets Manager secret ID for Proxmox credentials"
  type        = string
  default     = "dev/proxmox/terraform-token"
}

variable "node_name" {
  description = "Proxmox node name"
  type        = string
  default     = "pve-dev"
}
