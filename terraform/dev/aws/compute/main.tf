data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = var.remote_state_bucket
    key    = "${var.environment}/aws/network/terraform.tfstate"
    region = var.remote_state_region
  }
}

data "terraform_remote_state" "iam" {
  backend = "s3"
  config = {
    bucket = var.remote_state_bucket
    key    = "${var.environment}/aws/iam/terraform.tfstate"
    region = var.remote_state_region
  }
}



resource "aws_security_group" "wireguard" {
  name        = "wireguard-sg-${var.environment}"
  description = "WireGuard VPN EC2 security group"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  tags = {
    Name = "wireguard-sg-${var.environment}"
  }
}

# WireGuard UDP port - tunnel traffic
resource "aws_vpc_security_group_ingress_rule" "wireguard_udp" {
  security_group_id = aws_security_group.wireguard.id
  cidr_ipv4         = var.allowed_ip
  ip_protocol       = "udp"
  from_port         = var.wireguard_port
  to_port           = var.wireguard_port
}

# SSH access for management
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

resource "aws_key_pair" "vpn" {
  key_name   = "vpn-key-pair-${var.environment}"
  public_key = var.vpn_public_key
}

resource "aws_instance" "wireguard" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  availability_zone      = var.availability_zone
  subnet_id              = data.terraform_remote_state.network.outputs.subnet_vpn_id
  vpc_security_group_ids = [aws_security_group.wireguard.id]
  key_name               = aws_key_pair.vpn.key_name
  source_dest_check      = false
  iam_instance_profile   = data.terraform_remote_state.iam.outputs.wireguard_instance_profile_name

  user_data = <<-EOF
    #!/bin/bash
    # WireGuard pre-setup (packages + IP forwarding)
    dnf install -y wireguard-tools tcpdump nmap-ncat cronie iptables
    systemctl enable crond
    systemctl start crond
    sysctl -w net.ipv4.ip_forward=1
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    mkdir -p /etc/wireguard
    echo "WireGuard packages installed. Run setup-wireguard.sh to complete configuration."
  EOF

  tags = {
    Name = "wireguard-${var.environment}"
  }
}

resource "aws_eip" "wireguard" {
  domain = "vpc"

  tags = {
    Name = "wireguard-eip-${var.environment}"
  }
}

resource "aws_eip_association" "wireguard" {
  instance_id   = aws_instance.wireguard.id
  allocation_id = aws_eip.wireguard.id
}

resource "aws_route" "home_subnets" {
  route_table_id         = data.terraform_remote_state.network.outputs.rt_public_id
  destination_cidr_block = var.home_cidr
  network_interface_id   = aws_instance.wireguard.primary_network_interface_id
}

