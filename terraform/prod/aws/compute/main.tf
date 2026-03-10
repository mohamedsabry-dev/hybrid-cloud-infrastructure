data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "hybrid-cloud-infrastructure-tf-state-prod"
    key    = "prod/aws/network/terraform.tfstate"
    region = "eu-west-2"
  }
}


resource "aws_security_group" "wireguard" {
  name        = "prod-wireguard-sg"
  description = "WireGuard VPN EC2 security group"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  tags = {
    Name = "prod-wireguard-sg"
  }
}

# WireGuard UDP port - tunnel traffic
resource "aws_vpc_security_group_ingress_rule" "wireguard_udp" {
  security_group_id = aws_security_group.wireguard.id
  cidr_ipv4         = var.allowed_ip
  ip_protocol       = "udp"
  from_port         = 51820
  to_port           = 51820
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

resource "aws_instance" "wireguard" {
  ami                    = "ami-087c9ba923d9765d8"
  instance_type          = "t2.micro"
  availability_zone      = "eu-west-2a"
  subnet_id              = data.terraform_remote_state.network.outputs.subnet_vpn_id
  vpc_security_group_ids = [aws_security_group.wireguard.id]
  key_name               = "vpn-key-pair-prod"
  source_dest_check      = false

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
    Name = "prod-wireguard"
  }
}

resource "aws_eip" "wireguard" {
  domain = "vpc"

  tags = {
    Name = "prod-wireguard-eip"
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
