#===============================================================================
# Outputs
#===============================================================================

output "lxc_container" {
  description = "LXC container details"
  value = {
    ctid     = proxmox_virtual_environment_container.lxc_golden.vm_id
    hostname = var.lxc_container.hostname
    ip       = var.lxc_container.ip
    node     = var.node_name
    status   = proxmox_virtual_environment_container.lxc_golden.started ? "running" : "stopped"

    setup_instructions = <<-EOT
    1. SSH to container: ssh root@${split("/", var.lxc_container.ip)[0]}
    2. Install packages manually or run setup script
    3. Stop container: pct stop ${var.lxc_container.ctid}
    4. Convert to template: pct template ${var.lxc_container.ctid}

    Or run the automated script:
      proxmox/golden_templates/golden-lxc-setup.sh
    EOT

    clone_command      = "pct clone ${var.lxc_container.ctid} <new-ctid> --hostname <name> --full"
    template_command   = "pct template ${var.lxc_container.ctid}"
  }
}
