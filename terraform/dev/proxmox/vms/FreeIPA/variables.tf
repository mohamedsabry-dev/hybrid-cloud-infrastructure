#===============================================================================
# Test VM Configuration
#===============================================================================

variable "test_vm" {
  description = "Configuration for test VM cloned from golden image"
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
    vmid    = 101
    name    = "test-vm-01"
    cores   = 2
    memory  = 2048
    ip      = "10.0.63.98/24"
    gateway = "10.0.63.1"
    bridge  = "vmbr0"
    vlan_id = 63
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
  default     = ["10.0.5.1", "1.1.1.1"]
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

variable "proxmox_ssh_secret_id" {
  description = "AWS Secrets Manager secret ID for Proxmox SSH password"
  type        = string
  default     = "dev/proxmox/ssh-admin-password"
}

variable "vm_root_secret_id" {
  description = "AWS Secrets Manager secret ID for VM root password"
  type        = string
  default     = "dev/proxmox/vm-root-password"
}

variable "proxmox_ssh_username" {
  description = "Proxmox SSH username for snippet uploads"
  type        = string
  default     = "admin_dev"
}

variable "proxmox_secret_id" {
  description = "AWS Secrets Manager secret ID for Proxmox API token"
  type        = string
  default     = "dev/proxmox/terraform-token"
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