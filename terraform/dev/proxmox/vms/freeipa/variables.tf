#===============================================================================
# freeipa VM Configuration
#===============================================================================

variable "freeipa" {
  description = "Configuration for freeipa VM cloned from golden image"
  type = object({
    vmid    = number
    name    = string
    cores   = number
    memory  = number
    ip      = string
    gateway = string
    bridge  = string
    vlan_id = number
  })

  default = {
    vmid    = 1001
    name    = "freeipa"
    cores   = 2
    memory  = 1536
    ip      = "10.0.60.10/24"
    gateway = "10.0.60.1"
    bridge  = "vmbr0"
    vlan_id = 60
  }
}

variable "template_vmid" {
  description = "VM ID of the golden image template to clone from"
  type        = number
  default     = 9000
}

variable "template_name" {
  description = "Name of the golden image template (for documentation)"
  type        = string
  default     = "rocky10-golden-image"
}

variable "dns_servers" {
  description = "DNS servers for VMs"
  type        = list(string)
  default     = ["8.8.8.8", "1.1.1.1"]
}

variable "search_domain" {
  description = "DNS search domain"
  type        = string
  default     = "lab.local"
}

# Reuse from golden-image module
variable "node_name" {
  description = "Proxmox node name"
  type        = string
  default     = "pve-dev"
}

variable "datastore_id" {
  description = "Datastore for cloud-init config"
  type        = string
  default     = "local-lvm"
}


variable "proxmox_api_url" {
  description = "Proxmox API endpoint URL"
  type        = string
  default     = "https://pve-dev.lab.local:8006"
}

variable "proxmox_tls_insecure" {
  description = "Skip TLS verification for Proxmox API"
  type        = bool
  default     = true
}

variable "proxmox_api_token" {
  type      = string
  sensitive = true
}

variable "ansible_ssh_public_key" {
  description = "Ansible VM SSH public key for automated management"
  type        = string
  sensitive   = true
}

variable "vm_root_password" {
  description = "Root password for VM console access"
  type        = string
  sensitive   = true
}
