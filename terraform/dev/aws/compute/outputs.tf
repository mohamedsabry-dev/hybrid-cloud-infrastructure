output "wireguard_public_ip" {
  description = "Public IP of the WireGuard VPN server"
  value       = aws_eip.wireguard.public_ip
  sensitive   = true
}

output "wireguard_instance_id" {
  description = "Instance ID of the WireGuard server"
  value       = aws_instance.wireguard.id
}

output "wireguard_security_group_id" {
  description = "Security group ID for the WireGuard server"
  value       = aws_security_group.wireguard.id
}

output "wireguard_private_ip" {
  description = "Private IP of WireGuard instance (for VPC routing)"
  value       = aws_instance.wireguard.private_ip
}
