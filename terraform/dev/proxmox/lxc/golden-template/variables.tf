#===============================================================================
# LXC Container Configuration
#===============================================================================

variable "lxc_container" {
  description = "Configuration for LXC container"
  type = object({
    ctid        = number
    hostname    = string
    cores       = number
    memory      = number
    swap        = number
    rootfs_size = number
    bridge      = string
    vlan_id     = number
    ip          = string
    gateway     = string
  })

  default = {
    ctid        = 9001
    hostname    = "rocky10-lxc-golden"
    cores       = 1
    memory      = 1024
    swap        = 256
    rootfs_size = 10
    bridge      = "vmbr0"
    vlan_id     = 63
    ip          = "10.0.63.97/24"
    gateway     = "10.0.63.1"
  }
}

variable "template_file" {
  description = "Path to LXC template file on Proxmox"
  type        = string
  default     = "local:vztmpl/rockylinux-10-default_20251001_amd64.tar.xz"
}

#===============================================================================
# Proxmox Node Configuration
#===============================================================================

variable "node_name" {
  description = "Proxmox node name"
  type        = string
  default     = "pve-dev"
}

variable "datastore_id" {
  description = "Proxmox datastore for container rootfs"
  type        = string
  default     = "local-lvm"
}

#===============================================================================
# Proxmox Connection
#===============================================================================

variable "proxmox_secret_id" {
  description = "AWS Secrets Manager secret ID for Proxmox API token"
  type        = string
  default     = "dev/proxmox/terraform-token"
}

variable "proxmox_ssh_secret_id" {
  description = "AWS Secrets Manager secret ID for Proxmox SSH password"
  type        = string
  default     = "dev/proxmox/ssh-admin-password"
}

variable "proxmox_ssh_username" {
  description = "Proxmox SSH username"
  type        = string
  default     = "admin_dev"
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

variable "lxc_root_password" {
  description = "The root password for the LXC container, injected via CI/CD"
  type        = string
  sensitive   = true
}