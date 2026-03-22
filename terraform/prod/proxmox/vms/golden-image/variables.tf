# variables.tf

#===============================================================================
# Golden Image VM Configuration
#===============================================================================

variable "golden_image" {
  description = "Configuration for Rocky Linux 10.1 golden image VM"
  type = object({
    vm_id       = number
    name        = string
    tags        = list(string)
    description = string
    cpu_cores   = number
    memory      = number
    disk_size   = number
    bridge      = string
    vlan_id     = number
  })
  
  default = {
    vm_id       = 9000
    name        = "rocky10-golden-image"
    tags        = ["vm", "golden", "template", "prod"]
    description = "Rocky Linux 10.1 Golden Image - Install from ISO, run cleanup script, then convert to template"
    cpu_cores   = 2
    memory      = 2048
    disk_size   = 20
    bridge      = "vmbr0"
    vlan_id     = 53
  }
}

#===============================================================================
# Proxmox Node Configuration
#===============================================================================

variable "node_name" {
  description = "Proxmox node name where VM will be created"
  type        = string
  default     = "pve-prod"
}

variable "datastore_id" {
  description = "Proxmox datastore ID for VM disk"
  type        = string
  default     = "local-lvm"
}

#===============================================================================
# ISO Configuration
#===============================================================================

variable "iso_file_id" {
  description = "Proxmox ISO file ID for Rocky Linux 10.1"
  type        = string
  default     = "nas-iso:iso/Rocky-10.1-x86_64-minimal.iso"
}


variable "proxmox_api_url" {
  description = "Proxmox API endpoint URL"
  type        = string
  default     = "https://pve-prod.lab.local:8006"
}

variable "proxmox_tls_insecure" {
  description = "Skip TLS verification for Proxmox API (self-signed cert)"
  type        = bool
  default     = true
}

variable "proxmox_api_token" {
  type      = string
  sensitive = true
}