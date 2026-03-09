data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "hybrid-cloud-infrastructure-tf-state-dev"
    key    = "dev/aws/network/terraform.tfstate"
    region = "eu-west-2"
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}


resource "aws_security_group" "wireguard" {
  name        = "dev-wireguard-sg"
  description = "WireGuard VPN EC2 security group"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  tags = {
    Name = "dev-wireguard-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "wireguard_udp" {
  security_group_id = aws_security_group.wireguard.id
  cidr_ipv4         = var.allowed_ip
  ip_protocol       = "udp"
  from_port         = 51820
  to_port           = 51820
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.wireguard.id
  cidr_ipv4         = var.allowed_ip
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "allow_all" {
  security_group_id = aws_security_group.wireguard.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_instance" "wireguard" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  availability_zone      = "eu-west-2a"
  subnet_id              = data.terraform_remote_state.network.outputs.subnet_vpn_id
  vpc_security_group_ids = [aws_security_group.wireguard.id]
  key_name               = "vpn-key-pair"
  source_dest_check      = false

  tags = {
    Name = "dev-wireguard"
  }
}

resource "aws_eip" "wireguard" {
  domain = "vpc"

  tags = {
    Name = "dev-wireguard-eip"
  }
}

resource "aws_eip_association" "wireguard" {
  instance_id   = aws_instance.wireguard.id
  allocation_id = aws_eip.wireguard.id
}

resource "aws_route" "home_subnets" {
  route_table_id         = data.terraform_remote_state.network.outputs.rt_public_id
  destination_cidr_block = "10.0.0.0/16"
  network_interface_id   = aws_instance.wireguard.primary_network_interface_id
}