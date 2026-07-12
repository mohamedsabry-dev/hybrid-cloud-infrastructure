#!/bin/bash
set -euo pipefail

SCRIPT_LOG="/var/log/phase1-config-db.log"
exec >> "${SCRIPT_LOG}" 2>&1

echo "== Configuring PostgreSQL =="

# ---- Initialize DB ----
echo "[1/4] Initializing database..."
sudo postgresql-setup --initdb

# ---- Start and enable ----
echo "[2/4] Starting PostgreSQL..."
sudo systemctl enable --now postgresql

# ---- Create database and table ----
echo "[3/4] Creating database, table, and test data..."
sudo -u postgres psql <<'SQL'
CREATE DATABASE webstore;
\c webstore
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    price NUMERIC(10,2)
);
INSERT INTO products (name, price) VALUES
    ('Laptop', 999.99),
    ('Keyboard', 49.99),
    ('Monitor', 299.99);
SQL

# ---- Create app user ----
echo "[4/4] Creating webuser with SELECT-only access..."
sudo -u postgres psql <<'SQL'
CREATE USER webuser WITH PASSWORD 'web123';
GRANT CONNECT ON DATABASE webstore TO webuser;
\c webstore
GRANT SELECT ON products TO webuser;
SQL

# ---- Enable query logging (for evidence/debugging) ----
# log_statement = 'all' makes PostgreSQL log every SQL query it receives.
# pg_reload_conf() reloads the config without restarting the service.
# Logs go to: /var/lib/pgsql/data/log/postgresql-*.log
echo "[5/4] Enabling query logging..."
sudo -u postgres psql -c "ALTER SYSTEM SET log_statement = 'all';"
sudo -u postgres psql -c "SELECT pg_reload_conf();"

# ---- pg_hba.conf: allow password auth over TCP ----
# Default is 'ident' which checks OS username — PHP-FPM runs as 'apache', not 'webuser'.
# Change to 'md5' so PostgreSQL accepts username/password auth over TCP (127.0.0.1).
# File: /var/lib/pgsql/data/pg_hba.conf
# Change: host all all 127.0.0.1/32 ident → md5
# Then: sudo systemctl restart postgresql

echo "== PostgreSQL configured =="
