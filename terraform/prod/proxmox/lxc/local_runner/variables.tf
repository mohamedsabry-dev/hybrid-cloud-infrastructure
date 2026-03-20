#===============================================================================
# local_runner LXC Configuration
#===============================================================================

variable "local_runner" {
  description = "Configuration for local_runner LXC container from golden template"
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
    ctid            = 2002
    name            = "local-runner"
    cores           = 1
    memory          = 512
    swap            = 512
    ip              = "10.0.53.20/24"
    gateway         = "10.0.53.1"
    bridge          = "vmbr0"
    vlan_id         = 53
    startup_delay   = 60
    shutdown_delay  = 60
    startup_order   = 3
    started = true
    on_boot = true
  }
}

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
  default     = "pve-prod"
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
      size         = 15
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
      path   = "/opt/local_runner"
      backup = true
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
