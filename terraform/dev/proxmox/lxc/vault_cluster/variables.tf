#===============================================================================
# Vault Cluster LXC Configuration
#===============================================================================

#-------------------------------------------------------------------------------
# Vault 1
#-------------------------------------------------------------------------------
variable "vault1" {
  description = "Configuration for Vault 1 LXC container"
  type = object({
    ctid           = number
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
    ctid           = 2004
    name           = "vault1"
    cores          = 1
    memory         = 768
    ip             = "10.0.62.10/24"
    gateway        = "10.0.62.1"
    bridge         = "vmbr0"
    vlan_id        = 62
    startup_delay  = 60
    shutdown_delay = 60
    startup_order  = 5
    started        = true
    on_boot        = true
    stop_on_destroy = true
  }
}

#-------------------------------------------------------------------------------
# Vault 2
#-------------------------------------------------------------------------------
variable "vault2" {
  description = "Configuration for Vault 2 LXC container"
  type = object({
    ctid           = number
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
    ctid           = 2005
    name           = "vault2"
    cores          = 1
    memory         = 768
    ip             = "10.0.62.11/24"
    gateway        = "10.0.62.1"
    bridge         = "vmbr0"
    vlan_id        = 62
    startup_delay  = 60
    shutdown_delay = 60
    startup_order  = 6
    started        = true
    on_boot        = true
    stop_on_destroy = true
  }
}

#-------------------------------------------------------------------------------
# Vault 3
#-------------------------------------------------------------------------------
variable "vault3" {
  description = "Configuration for Vault 3 LXC container"
  type = object({
    ctid           = number
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
    ctid           = 2006
    name           = "vault3"
    cores          = 1
    memory         = 768
    ip             = "10.0.62.12/24"
    gateway        = "10.0.62.1"
    bridge         = "vmbr0"
    vlan_id        = 62
    startup_delay  = 60
    shutdown_delay = 60
    startup_order  = 7
    started        = true
    on_boot        = true
    stop_on_destroy = true
  }
}

#-------------------------------------------------------------------------------
# Common Variables
#-------------------------------------------------------------------------------
variable "template_ctid" {
  description = "Container ID of the golden LXC template to clone from"
  type        = number
  default     = 9001
}

variable "template_name" {
  description = "Name of the golden LXC template (for documentation)"
  type        = string
  default     = "rocky10-lxc-golden"
}

variable "dns_servers" {
  description = "DNS servers for container"
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
  description = "Map of disk configurations for the LXC"
  type = map(object({
    datastore_id = string
    size         = number
  }))

  default = {
    os_disk = {
      datastore_id = "local-lvm"
      size         = 10
    }
  }
}

variable "mount_points" {
  description = "Map of mount point configurations for the LXC"
  type = map(object({
    volume = string
    size   = string
    path   = string
  }))

  default = {
    mount_1 = {
      volume = "nas-dev-data"
      size   = "5G"
      path   = "/opt/vault"
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
