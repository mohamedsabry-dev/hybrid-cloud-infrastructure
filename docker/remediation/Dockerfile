FROM python:3.11-slim

# Install system dependencies and kubectl
RUN apt-get update && \
    apt-get install -y curl ca-certificates && \
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/ && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip install --no-cache-dir \
    kubernetes \
    requests \
    proxmoxer

# Script will be mounted via ConfigMap at /scripts/remediation.py
# This keeps image static and logic updatable without rebuild
CMD ["python", "/scripts/remediation.py"]