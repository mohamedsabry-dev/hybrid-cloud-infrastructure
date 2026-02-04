variable "proxmox_api_url" {
  type        = string
  default     = "https://pve-master.lab.local:8006"
  description = "Proxmox API URL"
}

variable "proxmox_api_token_id" {
  type        = string
  sensitive   = true
  description = "Proxmox API token ID (from AWS Secrets Manager)"
}

variable "proxmox_api_token_secret" {
  type        = string
  sensitive   = true
  description = "Proxmox API token secret (from AWS Secrets Manager)"
}

variable "proxmox_node" {
  type        = string
  default     = "pve-master"
  description = "Proxmox node name"
}
