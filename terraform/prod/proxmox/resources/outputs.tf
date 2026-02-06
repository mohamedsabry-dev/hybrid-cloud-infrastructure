output "nodes" {
  description = "List of Proxmox nodes in the cluster"
  value       = data.proxmox_virtual_environment_nodes.all.names
}

output "datastores" {
  description = "List of datastores on the first node"
  value       = [for ds in data.proxmox_virtual_environment_datastores.all.datastores : ds.id]
}
