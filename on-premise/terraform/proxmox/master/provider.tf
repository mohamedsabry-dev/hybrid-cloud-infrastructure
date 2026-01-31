# Proxmox Provider Configuration
# Credentials via environment variables:
#   PROXMOX_VE_ENDPOINT
#   PROXMOX_VE_USERNAME
#   PROXMOX_VE_PASSWORD
# Or via terraform.tfvars (not committed to git)

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  username = var.proxmox_username
  password = var.proxmox_password
  insecure = var.proxmox_insecure # Allow self-signed certs in homelab

  # SSH connection for certain operations (file uploads, etc.)
  ssh {
    agent    = true
    username = "root"
  }
}
