#!/bin/bash
set -euo pipefail

# --- Block 1: Logging setup ---
SCRIPT_LOG="/var/log/phase1-install.log"
exec >> "${SCRIPT_LOG}" 2>&1


echo "== Phase 1: Installing Web Stack Components =="
echo "Target: Rocky 10 (Test2 VM)"
echo ""

# ---- PostgreSQL ----
echo "[1/4] Installing PostgreSQL..."
sudo dnf install -y postgresql-server postgresql
echo "PostgreSQL installed."

# ---- Apache (httpd) + PHP ----
echo "[2/4] Installing Apache + PHP..."
sudo dnf install -y httpd php php-pgsql
echo "Apache + PHP installed."

# ---- Nginx ----
echo "[3/4] Installing Nginx..."
sudo dnf install -y nginx
echo "Nginx installed."

# ---- Varnish ----
echo "[4/4] Installing Varnish..."
sudo dnf install -y varnish
echo "Varnish installed."

echo ""
echo "== All 4 packages installed =="
echo "Versions:"
psql --version
httpd -v
nginx -v
varnishd -V 2>&1 | head -1
