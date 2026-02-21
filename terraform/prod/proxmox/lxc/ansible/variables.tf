#===============================================================================
# Ansible LXC Configuration
#===============================================================================

variable "ansible" {
  description = "Configuration for Ansible LXC container cloned from golden template"
  type = object({
    ctid    = number
    name    = string
    cores   = number
    memory  = number
    ip      = string
    gateway = string
    bridge  = string
    vlan_id = number
  })

  default = {
    ctid    = 2001
    name    = "ansible"
    cores   = 1
    memory  = 768
    ip      = "10.0.53.10/24"
    gateway = "10.0.53.1"
    bridge  = "vmbr0"
    vlan_id = 53
  }
}

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

# Reuse from golden-template module
variable "node_name" {
  description = "Proxmox node name"
  type        = string
  default     = "pve-prod"
}

variable "datastore_id" {
  description = "Datastore for container storage"
  type        = string
  default     = "local-lvm"
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
