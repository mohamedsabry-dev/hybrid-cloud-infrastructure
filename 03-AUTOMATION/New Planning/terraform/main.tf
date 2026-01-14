terraform {
  required_providers {
    vsphere = {
      source  = "hashicorp/vsphere"
      version = "~> 2.0" # Use the latest stable version
    }
  }
}




provider "vsphere" {
  user           = "administrator@vsphere.local"
  password       = "REDACTED_PASSWORD"
  vsphere_server = "vcenter.home.lab"

  # Set to true if your vCenter uses a self-signed certificate
  allow_unverified_ssl = true
}


data "vsphere_datacenter" "dc" {
  name = "Datacenter"
}

data "vsphere_datastore" "datastore" {
  name          = "NFS DS"
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_compute_cluster" "cluster" {
  name          = "Cluster"
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network" {
  name          = "VM Network"
  datacenter_id = data.vsphere_datacenter.dc.id
}


output "datacenter_id" {
  value = data.vsphere_datacenter.dc.id
}

output "datastore_id" {
  value = data.vsphere_datastore.datastore.id
}

output "network_id" {
  value = data.vsphere_network.network.id
}

data "vsphere_datastore" "iso_datastore" {
  name          = "NFS DS" # The name of the datastore where your ISO lives
  datacenter_id = data.vsphere_datacenter.dc.id
}

resource "vsphere_virtual_machine" "vm" {
  name             = "my-new-vm"
  
  # Use the ID from your cluster data source
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  
  # Use the ID from your datastore data source
  datastore_id     = data.vsphere_datastore.datastore.id

  num_cpus = 2
  memory   = 4096
  guest_id = "other3xLinux64Guest"

# Add this block:
  cdrom {
    datastore_id = data.vsphere_datastore.iso_datastore.id
    path         = "Rocky-10.0-x86_64-dvd1.iso" # Folder/FileName.iso
  }

  network_interface {
    # Use the ID from your network data source
    network_id = data.vsphere_network.network.id
  }

  disk {
    label = "disk0"
    size  = 20
  }
}