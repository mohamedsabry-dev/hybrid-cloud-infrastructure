## Identify test for the whole resources of the proxmox server include [Network, Compute, Storage, Users]

# Add provider block
################################################################################################
################################################################################################


################################################################################################
################################################################################################


# Add the main block of Data source query
################################################################################################

# Node Info
data "proxmox_virtual_environment_nodes" "all" {}

# Network - DNS settings
data "proxmox_virtual_environment_dns" "dns" {
  node_name = var.node_name
}

# Network - Interfaces via Proxmox API
data "external" "network_interfaces" {
  program = ["bash", "-c", <<-EOF
    curl -sk \
      -H "Authorization: PVEAPIToken=${local.proxmox_creds.token_id}=${local.proxmox_creds.token_secret}" \
      "${var.proxmox_api_url}/api2/json/nodes/${var.node_name}/network" \
    | jq -c '{
        interfaces: ([.data[].iface] | join(",")),
        bridges: ([.data[] | select(.type == "bridge") | .iface] | join(",")),
        bonds: ([.data[] | select(.type == "bond") | .iface] | join(",")),
        eths: ([.data[] | select(.type == "eth") | .iface] | join(","))
      }'
  EOF
  ]
}

# Storage - Datastores
data "proxmox_virtual_environment_datastores" "all" {
  node_name = var.node_name
}

# Compute - VMs
data "proxmox_virtual_environment_vms" "all" {}

# Compute - Containers
data "proxmox_virtual_environment_containers" "all" {}

# Access - Roles
data "proxmox_virtual_environment_roles" "all" {}

# Access - Users
data "proxmox_virtual_environment_users" "all" {}

################################################################################################
# Add the Output block to
################################################################################################

output "nodes" {
  description = "All Proxmox nodes"
  value       = data.proxmox_virtual_environment_nodes.all.names
}

output "dns" {
  description = "DNS settings on node"
  value       = data.proxmox_virtual_environment_dns.dns
}

output "network_interfaces" {
  description = "Network interfaces on node"
  value = {
    all     = data.external.network_interfaces.result.interfaces
    bridges = data.external.network_interfaces.result.bridges
    bonds   = data.external.network_interfaces.result.bonds
    eths    = data.external.network_interfaces.result.eths
  }
}

output "datastores" {
  description = "Available datastores"
  value       = data.proxmox_virtual_environment_datastores.all.datastores
}

output "vms" {
  description = "All VMs"
  value       = data.proxmox_virtual_environment_vms.all.vms
}

output "containers" {
  description = "All containers"
  value       = data.proxmox_virtual_environment_containers.all.containers
}

output "roles" {
  description = "Available roles"
  value       = data.proxmox_virtual_environment_roles.all.role_ids
}

output "users" {
  description = "All users"
  value       = data.proxmox_virtual_environment_users.all.user_ids
}

################################################################################################
# Add the variable block
################################################################################################

variable "node_name" {
  description = "Proxmox node name"
  type        = string
  default     = "pve-dev"
}
