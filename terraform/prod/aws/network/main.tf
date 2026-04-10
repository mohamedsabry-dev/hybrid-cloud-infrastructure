resource "aws_vpc" "vpc_main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true

  tags = {
    Name = "vpc-main-${var.environment}"
  }
}

resource "aws_internet_gateway" "igw_main" {
  vpc_id = aws_vpc.vpc_main.id

  tags = {
    Name = "igw-main-${var.environment}"
  }
}

resource "aws_subnet" "subnet_vpn" {
  vpc_id            = aws_vpc.vpc_main.id
  cidr_block        = var.subnet_vpn_cidr
  availability_zone = var.availability_zone

  tags = {
    Name = "subnet-vpn-${var.environment}"
  }
}

resource "aws_subnet" "subnet_mgmt" {
  vpc_id            = aws_vpc.vpc_main.id
  cidr_block        = var.subnet_mgmt_cidr
  availability_zone = var.availability_zone

  tags = {
    Name = "subnet-mgmt-${var.environment}"
  }
}

resource "aws_route_table" "rt_public" {
  vpc_id = aws_vpc.vpc_main.id

  tags = {
    Name = "rt-public-${var.environment}"
  }
}

resource "aws_route" "internet" {
  route_table_id         = aws_route_table.rt_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw_main.id
}

resource "aws_route_table_association" "rta_vpn" {
  subnet_id      = aws_subnet.subnet_vpn.id
  route_table_id = aws_route_table.rt_public.id
}

resource "aws_route_table_association" "rta_mgmt" {
  subnet_id      = aws_subnet.subnet_mgmt.id
  route_table_id = aws_route_table.rt_public.id
}

resource "aws_route53_zone" "private" {
  name = "lab.local"

  vpc {
    vpc_id = aws_vpc.vpc_main.id
    vpc_region = var.aws_region
  }
}

locals {
  dns_records = ["nginx-test", "nginx", "prometheus", "grafana", "loki", "wordpress"]
}

resource "aws_route53_record" "services" {
  for_each = toset(local.dns_records)

  zone_id = aws_route53_zone.private.zone_id
  name    = "${each.key}-prod"
  type    = "A"
  ttl     = 300
  records = [var.dns_ingress_ip]
}
