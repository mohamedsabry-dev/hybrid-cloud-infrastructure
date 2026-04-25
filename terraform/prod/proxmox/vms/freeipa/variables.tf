#===============================================================================
# freeipa VM Configuration
#===============================================================================

variable "tags" {
  description = "Tags for the VM [type, service, category, environment]"
  type        = list(string)
  default     = ["vm", "freeipa", "identity", "prod"]
}

variable "freeipa" {
  description = "Configuration for freeipa VM cloned from golden image"
  type = object({
    vmid            = number
    name            = string
    cores           = number
    memory          = number
    ip              = string
    gateway         = string
    bridge          = string
    vlan_id         = number
    startup_delay   = number
    shutdown_delay  = number
    startup_order   = number
    started         = bool
    on_boot         = bool
    stop_on_destroy = bool
  })

  default = {
    vmid            = 1001
    name            = "freeipa"
    cores           = 2
    memory          = 3072
    ip              = "10.0.50.10/24"
    gateway         = "10.0.50.1"
    bridge          = "vmbr0"
    vlan_id         = 50
    startup_delay   = 60      # Delay next containers after FreeIPA
    shutdown_delay  = 60
    startup_order   = 2       # Boots after Ansible's 5 min delay (NAS ready)
    started         = true
    on_boot         = true
    stop_on_destroy = true
  }
}
#
variable "template_vmid" {
  description = "VM ID of the golden image template to clone from (clone of source VM, not source itself)"
  type        = number
  default     = 9001
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
  default     = "pve-prod"
}

variable "disks" {
  description = "Map of disk configurations for the VM"
  type = map(object({
    datastore_id = string
    interface    = string
    size         = number
    ssd          = bool
    discard      = string
    file_format  = string
  }))

  default = {
    os_disk = {
      datastore_id = "local-lvm"
      interface    = "scsi0"
      size         = 25
      ssd          = true
      discard      = "on"
      file_format  = "raw"
    },
    data_disk = {
      datastore_id = "nas-prod-data"
      interface    = "scsi1"
      size         = 25
      ssd          = true
      discard      = "on"
      file_format  = "raw"
    }
  }
}

variable "proxmox_api_url" {
  description = "Proxmox API endpoint URL"
  type        = string
  default     = "https://pve-prod.lab.local:8006"
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
