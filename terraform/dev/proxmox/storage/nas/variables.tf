variable "nas_iso" {
  type = object({
    id      = string
    server  = string
    export  = string
    nodes   = list(string)
    content = list(string)
  })
  default = {
    id      = "nas-iso"
    server  = "10.0.40.120"
    export  = "/volume1/shared-iso"
    nodes   = ["pve-dev"]
    content = ["iso", "vztmpl"]
  }
}

variable "nas_data" {
  type = object({
    id        = string
    server    = string
    export    = string
    nodes     = list(string)
    content   = list(string)
    keep_last = number
  })
  default = {
    id        = "nas-dev-data"
    server    = "10.0.40.120"
    export    = "/volume1/dev-storage"
    nodes     = ["pve-dev"]
    content   = ["images", "rootdir", "backup"]
    keep_last = 2
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