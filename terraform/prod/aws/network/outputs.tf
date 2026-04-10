output "vpc_id" {
  description = "ID of the main VPC"
  value       = aws_vpc.vpc_main.id
}

output "vpc_cidr" {
  description = "CIDR block of the main VPC"
  value       = aws_vpc.vpc_main.cidr_block
}

output "subnet_vpn_id" {
  description = "ID of the VPN subnet"
  value       = aws_subnet.subnet_vpn.id
}

output "subnet_mgmt_id" {
  description = "ID of the management subnet"
  value       = aws_subnet.subnet_mgmt.id
}

output "rt_public_id" {
  description = "ID of the public route table"
  value       = aws_route_table.rt_public.id
}

output "igw_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.igw_main.id
}

output "aws_route53_records" {
  description = "DNS Records"
  value = [for i in aws_route53_record.services : i.fqdn]
}
