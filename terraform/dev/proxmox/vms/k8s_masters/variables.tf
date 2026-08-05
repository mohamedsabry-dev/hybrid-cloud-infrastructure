#===============================================================================
# K8s Control Plane Configuration
#===============================================================================

variable "tags" {
  description = "Tags for the VM [type, service, category, environment]"
  type        = list(string)
  default     = ["vm", "k8s-master", "kubernetes", "dev"]
}

#-------------------------------------------------------------------------------
# K8s Master 1
#-------------------------------------------------------------------------------
variable "k8s_master1" {
  description = "Configuration for K8s Master 1 VM"
  type = object({
    vmid           = number
    name           = string
    cores          = number
    memory         = number
    ip             = string
    gateway        = string
    bridge         = string
    vlan_id        = number
    startup_delay  = number
    shutdown_delay = number
    startup_order  = number
    started        = bool
    on_boot        = bool
    stop_on_destroy = bool
  })

  default = {
    vmid           = 1010
    name           = "k8s-master1"
    cores          = 4
    memory         = 2816  # Increased from 2048 to prevent control plane memory exhaustion.
    ip             = "10.0.61.10/24"
    gateway        = "10.0.61.1"
    bridge         = "vmbr0"
    vlan_id        = 61
    startup_delay  = 0       # All masters start together (parallel boot)
    shutdown_delay = 60
    startup_order  = 8       # All masters share same order for simultaneous start
    started        = false
    on_boot        = false
    stop_on_destroy = true
  }
}

#-------------------------------------------------------------------------------
# K8s Master 2
#-------------------------------------------------------------------------------
variable "k8s_master2" {
  description = "Configuration for K8s Master 2 VM"
  type = object({
    vmid           = number
    name           = string
    cores          = number
    memory         = number
    ip             = string
    gateway        = string
    bridge         = string
    vlan_id        = number
    startup_delay  = number
    shutdown_delay = number
    startup_order  = number
    started        = bool
    on_boot        = bool
    stop_on_destroy = bool
  })

  default = {
    vmid           = 1011
    name           = "k8s-master2"
    cores          = 4
    memory         = 2816  # Increased from 2048 to prevent control plane memory exhaustion.
    ip             = "10.0.61.11/24"
    gateway        = "10.0.61.1"
    bridge         = "vmbr0"
    vlan_id        = 61
    startup_delay  = 0       # All masters start together (parallel boot)
    shutdown_delay = 60
    startup_order  = 8       # All masters share same order for simultaneous start
    started        = true
    on_boot        = true
    stop_on_destroy = true
  }
}

#-------------------------------------------------------------------------------
# K8s Master 3
#-------------------------------------------------------------------------------
variable "k8s_master3" {
  description = "Configuration for K8s Master 3 VM"
  type = object({
    vmid           = number
    name           = string
    cores          = number
    memory         = number
    ip             = string
    gateway        = string
    bridge         = string
    vlan_id        = number
    startup_delay  = number
    shutdown_delay = number
    startup_order  = number
    started        = bool
    on_boot        = bool
    stop_on_destroy = bool
  })

  default = {
    vmid           = 1012
    name           = "k8s-master3"
    cores          = 4
    memory         = 2816  # Increased from 2048 to prevent control plane memory exhaustion.
    ip             = "10.0.61.12/24"
    gateway        = "10.0.61.1"
    bridge         = "vmbr0"
    vlan_id        = 61
    startup_delay  = 180      # Wait 180 after masters before starting workers (order 9)
    shutdown_delay = 60
    startup_order  = 8       # All masters share same order for simultaneous start
    started        = true
    on_boot        = true
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
  default     = "pve-dev"
}

variable "disks" {
  description = "Disk configuration for K8s masters (OS disk only)"
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
    }
  }
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
  description = "Ansible SSH public key for automated management"
  type        = string
  sensitive   = true
}

variable "vm_root_password" {
  description = "Root password for VM console access"
  type        = string
  sensitive   = true
}
