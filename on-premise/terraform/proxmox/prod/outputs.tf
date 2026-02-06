output "nodes" {
  description = "Available Proxmox nodes"
  value       = data.proxmox_virtual_environment_nodes.available.names
}

output "datastores" {
  description = "Available storage on node"
  value = [
    for ds in data.proxmox_virtual_environment_datastores.storage.datastores : {
      id        = ds.id
      type      = ds.type
      active    = ds.active
      shared    = ds.shared
      available = "${floor(ds.space_available / 1073741824)} GB"
      total     = "${floor(ds.space_total / 1073741824)} GB"
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
