variable "proxmox_api_url" {
  description = "Proxmox API URL (base URL without /api2/json)"
  type        = string
  default     = "https://pve-master:8006"
}

variable "proxmox_tls_insecure" {
  description = "Skip TLS verification (set false in production with valid certs)"
  type        = bool
  default     = true
}
