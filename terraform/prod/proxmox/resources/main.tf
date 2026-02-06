# Test: List Proxmox resources to verify connectivity

# Get all nodes in the cluster
data "proxmox_virtual_environment_nodes" "all" {}

# Get datastores/storage
data "proxmox_virtual_environment_datastores" "all" {
  node_name = data.proxmox_virtual_environment_nodes.all.names[0]
}
