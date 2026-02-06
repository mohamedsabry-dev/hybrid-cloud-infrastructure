# Fetch existing Proxmox resources to verify connectivity and display info

data "proxmox_virtual_environment_nodes" "available" {}

data "proxmox_virtual_environment_datastores" "storage" {
  node_name = var.proxmox_node
}

data "proxmox_virtual_environment_vms" "all" {
  node_name = var.proxmox_node
}

data "proxmox_virtual_environment_containers" "all" {
  node_name = var.proxmox_node
}
