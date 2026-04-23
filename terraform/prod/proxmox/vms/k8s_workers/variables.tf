#===============================================================================
# K8s Worker Nodes Configuration
#===============================================================================

variable "tags" {
  description = "Tags for the VM [type, service, category, environment]"
  type        = list(string)
  default     = ["vm", "k8s-worker", "kubernetes", "prod"]
}

#-------------------------------------------------------------------------------
# K8s Worker 1
#-------------------------------------------------------------------------------
variable "k8s_worker1" {
  description = "Configuration for K8s Worker 1 VM"
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
    vmid           = 1020
    name           = "k8s-worker1"
    cores          = 4
    memory         = 10240  # 10GB
    ip             = "10.0.54.10/24"
    gateway        = "10.0.54.1"
    bridge         = "vmbr0"
    vlan_id        = 54
    ip2            = "10.0.40.101/24"
    bridge2        = "vmbr1"
    vlan_id2       = 40
    startup_delay  = 0       # All workers start together (60s delay is on master3)
    shutdown_delay = 60
    startup_order  = 9       # All workers share same order, start after masters (order 8)
    started        = true
    on_boot        = true
    stop_on_destroy = true
  }
}

#-------------------------------------------------------------------------------
# K8s Worker 2
#-------------------------------------------------------------------------------
variable "k8s_worker2" {
  description = "Configuration for K8s Worker 2 VM"
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
    vmid           = 1021
    name           = "k8s-worker2"
    cores          = 4
    memory         = 10240  # 10GB
    ip             = "10.0.54.11/24"
    gateway        = "10.0.54.1"
    bridge         = "vmbr0"
    vlan_id        = 54
    ip2            = "10.0.40.102/24"
    bridge2        = "vmbr1"
    vlan_id2       = 40
    startup_delay  = 0       # All workers start together (parallel boot)
    shutdown_delay = 60
    startup_order  = 9       # All workers share same order, start after masters (order 8)
    started        = true
    on_boot        = true
    stop_on_destroy = true
  }
}

#-------------------------------------------------------------------------------
# K8s Worker 3
#-------------------------------------------------------------------------------
variable "k8s_worker3" {
  description = "Configuration for K8s Worker 3 VM"
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
    vmid           = 1022
    name           = "k8s-worker3"
    cores          = 4
    memory         = 10240  # 10GB
    ip             = "10.0.54.12/24"
    gateway        = "10.0.54.1"
    bridge         = "vmbr0"
    vlan_id        = 54
    ip2            = "10.0.40.103/24"
    bridge2        = "vmbr1"
    vlan_id2       = 40
    startup_delay  = 0       # All workers start together (parallel boot)
    shutdown_delay = 60
    startup_order  = 9       # All workers share same order, start after masters (order 8)
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
  default     = "pve-prod"
}

variable "disks" {
  description = "Disk configuration for K8s workers (OS disk only)"
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
