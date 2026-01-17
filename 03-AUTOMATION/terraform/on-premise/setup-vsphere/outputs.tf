# =============================================================================
# vSphere Connection Validation Outputs
# =============================================================================

output "connection_status" {
  description = "Confirms successful connection to vSphere"
  value       = "Successfully connected to vSphere server: ${var.vsphere_server}"
}

output "datacenter_id" {
  description = "The ID of the vSphere datacenter"
  value       = data.vsphere_datacenter.dc.id
}

output "datacenter_name" {
  description = "The name of the vSphere datacenter"
  value       = data.vsphere_datacenter.dc.name
}

# =============================================================================
# Infrastructure Summary
# =============================================================================

output "vsphere_info" {
  description = "Summary of vSphere infrastructure"
  value = {
    server     = var.vsphere_server
    datacenter = data.vsphere_datacenter.dc.name
  }
}