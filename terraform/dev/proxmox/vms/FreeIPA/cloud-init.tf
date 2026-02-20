#-------------------------------------------------------------------------------
# Cloud-Init Config
#-------------------------------------------------------------------------------


resource "proxmox_virtual_environment_file" "cloud_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.node_name

  source_raw {
    data = <<-EOF
#cloud-config
hostname: ${var.test_vm.name}
fqdn: ${var.test_vm.name}.lab.local

chpasswd:
  list: |
    root:${data.aws_secretsmanager_secret_version.vm_root.secret_string}
  expire: false

network:
  config: disabled

ssh_pwauth: true

runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
EOF

    file_name = "cloud-config-${var.test_vm.name}.yaml"
  }
}