# =============================================================================
# vSphere Data Sources - Fetch existing infrastructure data
# =============================================================================

# Datacenter
data "vsphere_datacenter" "dc" {
  name = var.datacenter_name
}

# All Clusters in the Datacenter
data "vsphere_compute_cluster" "clusters" {
  for_each      = toset(data.vsphere_datacenter.dc.id != "" ? ["cluster"] : [])
  name          = "cluster"
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Host Systems
data "vsphere_host" "hosts" {
  for_each      = toset([])  # Populate with host names if known
  name          = each.key
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Datastores
data "vsphere_datastore" "datastores" {
  for_each      = toset([])  # Populate with datastore names if known
  name          = each.key
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Networks
data "vsphere_network" "networks" {
  for_each      = toset([])  # Populate with network names if known
  name          = each.key
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Resource Pools
data "vsphere_resource_pool" "pools" {
  for_each      = toset([])  # Populate with resource pool paths if known
  name          = each.key
  datacenter_id = data.vsphere_datacenter.dc.id
}