FROM python:3.11-slim

# Pin kubectl explicitly — matches cluster v1.35.3. Do NOT use stable.txt (unpinned = surprise upgrades)
ARG KUBECTL_VERSION=v1.35.3

# Install system dependencies and kubectl
RUN apt-get update && \
    apt-get install -y curl ca-certificates iputils-ping traceroute dnsutils vim-tiny openssh-client jq netcat-openbsd procps && \
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/ && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install Python dependencies — PINNED. kubernetes 36.0.0 broke auth_settings()/bearer token auth
# in load_incluster_config(). Stay on 35.x until v36 migration is done deliberately.
RUN pip install --no-cache-dir \
    kubernetes==35.0.0 \
    urllib3==2.6.3 \
    requests==2.32.3 \
    proxmoxer==2.1.0

# Script will be mounted via ConfigMap at /scripts/remediation.py
# This keeps image static and logic updatable without rebuild
CMD ["python", "/scripts/remediation.py"]