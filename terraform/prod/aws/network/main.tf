resource "aws_vpc" "vpc_main" {
  cidr_block           = "172.17.0.0/16"  # Different CIDR from dev (172.16.0.0/16)
  enable_dns_hostnames = true

  tags = {
    Name = "prod-main"
  }
}

resource "aws_internet_gateway" "igw_main" {
  vpc_id = aws_vpc.vpc_main.id

  tags = {
    Name = "prod-igw"
  }
}

resource "aws_subnet" "subnet_vpn" {
  vpc_id            = aws_vpc.vpc_main.id
  cidr_block        = "172.17.65.0/24"
  availability_zone = "eu-west-2a"

  tags = {
    Name = "prod-vpn"
  }
}

resource "aws_subnet" "subnet_mgmt" {
  vpc_id            = aws_vpc.vpc_main.id
  cidr_block        = "172.17.63.0/24"
  availability_zone = "eu-west-2a"

  tags = {
    Name = "prod-mgmt"
  }
}

resource "aws_route_table" "rt_public" {
  vpc_id = aws_vpc.vpc_main.id

  tags = {
    Name = "prod-public-rt"
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
