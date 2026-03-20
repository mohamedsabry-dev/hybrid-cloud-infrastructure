#===============================================================================
# Vault Cluster LXC Configuration
#===============================================================================

#-------------------------------------------------------------------------------
# Vault 1
#-------------------------------------------------------------------------------
variable "vault1" {
  description = "Configuration for Vault 1 LXC container"
  type = object({
    ctid            = number
    name            = string
    cores           = number
    memory          = number
    swap            = number
    ip              = string
    gateway         = string
    bridge          = string
    vlan_id         = number
    startup_delay   = number
    shutdown_delay  = number
    startup_order   = number
    started = bool
    on_boot = bool
  })

  default = {
    ctid            = 2004
    name            = "vault1"
    cores           = 1
    memory          = 768
    swap            = 512
    ip              = "10.0.62.10/24"
    gateway         = "10.0.62.1"
    bridge          = "vmbr0"
    vlan_id         = 62
    startup_delay   = 60
    shutdown_delay  = 60
    startup_order   = 5
    started = true
    on_boot = true
  }
}

#-------------------------------------------------------------------------------
# Vault 2
#-------------------------------------------------------------------------------
variable "vault2" {
  description = "Configuration for Vault 2 LXC container"
  type = object({
    ctid            = number
    name            = string
    cores           = number
    memory          = number
    swap            = number
    ip              = string
    gateway         = string
    bridge          = string
    vlan_id         = number
    startup_delay   = number
    shutdown_delay  = number
    startup_order   = number
    started = bool
    on_boot = bool
  })

  default = {
    ctid            = 2005
    name            = "vault2"
    cores           = 1
    memory          = 768
    swap            = 512
    ip              = "10.0.62.11/24"
    gateway         = "10.0.62.1"
    bridge          = "vmbr0"
    vlan_id         = 62
    startup_delay   = 60
    shutdown_delay  = 60
    startup_order   = 6
    started = true
    on_boot = true
  }
}

#-------------------------------------------------------------------------------
# Vault 3
#-------------------------------------------------------------------------------
variable "vault3" {
  description = "Configuration for Vault 3 LXC container"
  type = object({
    ctid            = number
    name            = string
    cores           = number
    memory          = number
    swap            = number
    ip              = string
    gateway         = string
    bridge          = string
    vlan_id         = number
    startup_delay   = number
    shutdown_delay  = number
    startup_order   = number
    started = bool
    on_boot = bool
  })

  default = {
    ctid            = 2006
    name            = "vault3"
    cores           = 1
    memory          = 768
    swap            = 512
    ip              = "10.0.62.12/24"
    gateway         = "10.0.62.1"
    bridge          = "vmbr0"
    vlan_id         = 62
    startup_delay   = 60
    shutdown_delay  = 60
    startup_order   = 7
    started = true
    on_boot = true
  }
}

#-------------------------------------------------------------------------------
# Common Variables
#-------------------------------------------------------------------------------
variable "template" {
  description = "LXC template configuration"
  type = object({
    file_id = string
    os_type = string
  })
  default = {
    file_id = "nas-iso:vztmpl/rocky-9-lxc-golden.tar.gz"
    os_type = "centos"
  }
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

variable "ssh_public_keys" {
  description = "List of SSH public keys to inject into the container"
  type        = list(string)
  default     = []
}

variable "root_password" {
  description = "Root password for the container"
  type        = string
  sensitive   = true
  default     = null
}

variable "mount_points" {
  description = "Map of mount point configurations for the LXC"
  type = map(object({
    volume = string
    size   = string
    path   = string
    backup = bool
  }))

  default = {
    mount_1 = {
      volume = "local-lvm"
      size   = "5G"
      path   = "/opt/vault"
      backup = true
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
