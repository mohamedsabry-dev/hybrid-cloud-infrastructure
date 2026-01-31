# =============================================================================
# Proxmox Connection Variables
# =============================================================================

variable "proxmox_endpoint" {
  description = "Proxmox API endpoint URL"
  type        = string
  default     = "https://proxmox-master.home.lab:8006/"
}

variable "proxmox_username" {
  description = "Proxmox username (e.g., root@pam or terraform@pve)"
  type        = string
  default     = "root@pam"
}

variable "proxmox_password" {
  description = "Proxmox password"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification (for self-signed certs)"
  type        = bool
  default     = true
}

# =============================================================================
# Node Configuration
# =============================================================================

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "proxmox-master"
}

# =============================================================================
# Network Configuration
# =============================================================================

variable "network_bridges" {
  description = "Network bridge mapping"
  type = object({
    wan      = string
    internal = string
    vmotion  = string
  })
  default = {
    wan      = "vmbr0"
    internal = "vmbr1"
    vmotion  = "vmbr2"
  }
}

variable "internal_network" {
  description = "Internal network CIDR"
  type        = string
  default     = "10.0.20.0/24"
}

variable "internal_gateway" {
  description = "Internal network gateway (pfSense)"
  type        = string
  default     = "10.0.20.170"
}

# =============================================================================
# Storage Configuration
# =============================================================================

variable "default_storage" {
  description = "Default storage for VMs"
  type        = string
  default     = "local-lvm"
}

variable "iso_storage" {
  description = "Storage for ISO files"
  type        = string
  default     = "local"
}

variable "template_storage" {
  description = "Storage for VM templates"
  type        = string
  default     = "local-lvm"
}
