#===============================================================================
# test Nodes Configuration
#===============================================================================

variable "tags" {
  description = "Tags for the VM [type, service, category, environment]"
  type        = list(string)
  default     = ["vm", "test", "linux", "prod"]
}

#-------------------------------------------------------------------------------
# test1
#-------------------------------------------------------------------------------
variable "test1" {
  description = "Configuration for test1 VM"
  type = object({
    vmid           = number
    name           = string
    cores          = number
    memory         = number
    ip             = string
    gateway        = string
    bridge         = string
    vlan_id        = number
    ip2            = string
    bridge2        = string
    vlan_id2       = number
    startup_delay  = number
    shutdown_delay = number
    startup_order  = number
    started        = bool
    on_boot        = bool
    stop_on_destroy = bool
  })

  default = {
    vmid           = 1030
    name           = "test1"
    cores          = 2
    memory         = 3584  # 3.5GB # edited to carry docker
    ip             = "10.0.55.151/24"
    gateway        = "10.0.55.1"
    bridge         = "vmbr0"
    vlan_id        = 55
    ip2            = "10.0.40.151/24"
    bridge2        = "vmbr1"
    vlan_id2       = 40
    startup_delay  = 0
    shutdown_delay = 0
    startup_order  = 0
    started        = false
    on_boot        = false
    stop_on_destroy = true
  }
}

#-------------------------------------------------------------------------------
# test2
#-------------------------------------------------------------------------------
variable "test2" {
  description = "Configuration for test2 VM"
  type = object({
    vmid           = number
    name           = string
    cores          = number
    memory         = number
    ip             = string
    gateway        = string
    bridge         = string
    vlan_id        = number
    ip2            = string
    bridge2        = string
    vlan_id2       = number
    startup_delay  = number
    shutdown_delay = number
    startup_order  = number
    started        = bool
    on_boot        = bool
    stop_on_destroy = bool
  })

  default = {
    vmid           = 1031
    name           = "test2"
    cores          = 2
    memory         = 1536  # 1.5GB
    ip             = "10.0.55.152/24"
    gateway        = "10.0.55.1"
    bridge         = "vmbr0"
    vlan_id        = 55
    ip2            = "10.0.40.152/24"
    bridge2        = "vmbr1"
    vlan_id2       = 40
    startup_delay  = 0
    shutdown_delay = 0
    startup_order  = 0
    started        = false
    on_boot        = false
    stop_on_destroy = true
  }
}

#-------------------------------------------------------------------------------
# Common Variables
#-------------------------------------------------------------------------------
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

variable "node_name" {
  description = "Proxmox node name"
  type        = string
  default     = "pve-prod"
}

variable "disks" {
  description = "Disk configuration for test VMs"
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
      size         = 20
      ssd          = true
      discard      = "on"
      file_format  = "raw"
    }
    data_disk = {
      datastore_id = "local-lvm"
      interface    = "scsi1"
      size         = 5
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
  description = "Ansible SSH public key for automated management"
  type        = string
  sensitive   = true
}

variable "vm_root_password" {
  description = "Root password for VM console access"
  type        = string
  sensitive   = true
}
