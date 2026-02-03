output "nodes" {
  description = "Available Proxmox nodes"
  value       = data.proxmox_virtual_environment_nodes.available.names
}

output "datastores" {
  description = "Available storage on node"
  value       = data.proxmox_virtual_environment_datastores.storage.datastore_ids
}

output "networks" {
  description = "Network interfaces on node"
  value = [
    for iface in data.proxmox_virtual_environment_node_network.net.linux_bridges : {
      name   = iface.name
      cidr   = iface.cidr
      active = iface.active
    }
  ]
}

output "vms" {
  description = "Existing VMs on node"
  value = [
    for vm in data.proxmox_virtual_environment_vms.all.vms : {
      id     = vm.vm_id
      name   = vm.name
      status = vm.status
    }
  ]
}

output "containers" {
  description = "Existing containers on node"
  value = [
    for ct in data.proxmox_virtual_environment_containers.all.containers : {
      id     = ct.container_id
      name   = ct.name
      status = ct.status
    }
  ]
}
