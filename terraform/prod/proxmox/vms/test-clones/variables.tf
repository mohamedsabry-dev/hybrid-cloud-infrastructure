#===============================================================================
# Variables for Test VM Clones
#===============================================================================

variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
  default     = "https://pve-prod:8006"
}

variable "proxmox_tls_insecure" {
  description = "Skip TLS verification"
  type        = bool
  default     = true
}

variable "proxmox_secret_id" {
  description = "Secrets Manager secret ID for Proxmox credentials"
  type        = string
  default     = "prod/proxmox/terraform-token"
}

variable "node_name" {
  description = "Proxmox node name"
  type        = string
  default     = "pve-prod"
}

variable "template_vmid" {
  description = "VM ID of the golden image template"
  type        = number
  default     = 9000
}

#-------------------------------------------------------------------------------
# Test VMs Configuration
#-------------------------------------------------------------------------------
variable "test_vms" {
  description = "Map of test VMs to create"
  type = map(object({
    vmid     = number
    name     = string
    ip       = string
    gateway  = string
    vlan     = number
    cores    = number
    memory   = number
    disk     = number
  }))
  default = {
    "test-vm-01" = {
      vmid    = 101
      name    = "test-vm-01"
      ip      = "10.0.64.99/24"
      gateway = "10.0.64.1"
      vlan    = 64
      cores   = 2
      memory  = 2048
      disk    = 20
    }
    "test-vm-02" = {
      vmid    = 102
      name    = "test-vm-02"
      ip      = "10.0.63.99/24"
      gateway = "10.0.63.1"
      vlan    = 63
      cores   = 2
      memory  = 2048
      disk    = 20
    }
  }
}

variable "dns_servers" {
  description = "DNS servers for VMs"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "search_domain" {
  description = "DNS search domain"
  type        = string
  default     = "lab.local"
}
