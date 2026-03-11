output "rt_public_id" {
  value = aws_route_table.rt_public.id
}

output "vpc_id" {
  value = aws_vpc.vpc_main.id
}

output "subnet_vpn_id" {
  value = aws_subnet.subnet_vpn.id
}

output "subnet_mgmt_id" {
  value = aws_subnet.subnet_mgmt.id
}