#!/bin/bash
#===============================================================================
# Install Prometheus Exporters on Proxmox
# Run on each Proxmox host (DEV and PROD)
#===============================================================================

set -e

if [[ $EUID -ne 0 ]]; then
    echo "Run as root"
    exit 1
fi

echo "Installing Prometheus exporters..."

#===============================================================================
# Node Exporter (system metrics)
#===============================================================================
echo "Installing Node Exporter..."

NODE_EXPORTER_VERSION="1.7.0"
cd /tmp
wget -q https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
tar xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
cp node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
rm -rf node_exporter-${NODE_EXPORTER_VERSION}*

# Create systemd service
cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter

echo "Node Exporter installed on port 9100"

#===============================================================================
# PVE Exporter (Proxmox metrics)
#===============================================================================
echo "Installing PVE Exporter..."

apt update
apt install -y python3-pip python3-venv

# Create venv and install
python3 -m venv /opt/pve-exporter
/opt/pve-exporter/bin/pip install prometheus-pve-exporter

# Create config
mkdir -p /etc/pve-exporter
cat > /etc/pve-exporter/pve.yml << 'EOF'
default:
  user: root@pam
  token_name: prometheus
  token_value: REPLACE_WITH_TOKEN
  verify_ssl: false
EOF

chmod 600 /etc/pve-exporter/pve.yml

# Create systemd service
cat > /etc/systemd/system/pve_exporter.service << 'EOF'
[Unit]
Description=Prometheus PVE Exporter
After=network.target

[Service]
Type=simple
ExecStart=/opt/pve-exporter/bin/pve_exporter /etc/pve-exporter/pve.yml
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable pve_exporter

echo ""
echo "==============================================="
echo "MANUAL STEP REQUIRED"
echo "==============================================="
echo ""
echo "1. Create API token in Proxmox:"
echo "   Datacenter → Permissions → API Tokens → Add"
echo "   User: root@pam"
echo "   Token ID: prometheus"
echo "   Privilege Separation: unchecked"
echo ""
echo "2. Copy the token value and update:"
echo "   /etc/pve-exporter/pve.yml"
echo ""
echo "3. Start the exporter:"
echo "   systemctl start pve_exporter"
echo ""
echo "4. Verify:"
echo "   curl http://localhost:9100/metrics | head"
echo "   curl http://localhost:9221/pve | head"
echo ""
