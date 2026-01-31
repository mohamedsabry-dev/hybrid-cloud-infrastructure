# =============================================================================
# Outputs
# =============================================================================

output "proxmox_endpoint" {
  description = "Proxmox API endpoint"
  value       = var.proxmox_endpoint
}

output "proxmox_node" {
  description = "Proxmox node name"
  value       = var.proxmox_node
}

output "network_config" {
  description = "Network bridge configuration"
  value       = var.network_bridges
}
