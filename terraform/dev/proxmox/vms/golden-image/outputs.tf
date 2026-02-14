output "golden_image_vm" {
  description = "Golden image VM details"
  value = {
    vm_id     = proxmox_virtual_environment_vm.golden_image.vm_id
    name      = proxmox_virtual_environment_vm.golden_image.name
    node_name = proxmox_virtual_environment_vm.golden_image.node_name
  }
}

output "next_steps" {
  description = "Manual steps after VM creation"
  value       = <<-EOT
    1. Open Proxmox console for VM ${var.golden_image_vmid}
    2. Install Rocky Linux (minimal install, set root password)
    3. Configure network: IP 10.0.65.99/24, Gateway 10.0.65.1, VLAN 65
    4. Install qemu-guest-agent: dnf install -y qemu-guest-agent && systemctl enable --now qemu-guest-agent
    5. Install packages: dnf install -y curl wget vim htop git sudo bash-completion tar unzip openssh-server net-tools traceroute bind-utils tcpdump nmap-ncat
    6. Run cleanup script: infrastructure/compute/golden-image-setup.sh
    7. Shutdown VM and convert to template in Proxmox UI
  EOT
}
