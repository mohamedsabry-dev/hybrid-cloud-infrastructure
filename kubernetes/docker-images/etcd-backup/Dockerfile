FROM alpine:3.19

# etcd version for etcdctl
ARG ETCD_VERSION=v3.5.12

# Install common utilities and AWS CLI
RUN apk add --no-cache \
    aws-cli \
    bash \
    curl \
    ca-certificates \
    jq \
    openssl \
    bind-tools \
    iputils \
    netcat-openbsd \
    vim \
    grep \
    sed \
    gawk \
    findutils \
    coreutils \
    tar \
    gzip \
    && rm -rf /var/cache/apk/*

# Install etcdctl
RUN curl -L https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-amd64.tar.gz | \
    tar xz -C /tmp && \
    mv /tmp/etcd-${ETCD_VERSION}-linux-amd64/etcdctl /usr/local/bin/ && \
    chmod +x /usr/local/bin/etcdctl && \
    rm -rf /tmp/etcd-*

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/

# Verify installations
RUN etcdctl version && \
    aws --version && \
    kubectl version --client

ENTRYPOINT ["/bin/bash"]
