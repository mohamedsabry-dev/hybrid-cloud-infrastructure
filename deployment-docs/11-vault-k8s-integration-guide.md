# Vault - Kubernetes Integration Guide (DEV)

Note: This guide runs after both Vault and Kubernetes are fully deployed and operational.
See: 08-vault-setup-guide.md and 09-k8s-setup-guide.md

If you face issues during this integration, check: troubleshooting/vault/

---

## Overview

This guide covers the trust setup between HashiCorp Vault and Kubernetes, allowing
pods to authenticate to Vault using their Kubernetes service account identity.
Once complete, apps deployed on K8s can inject secrets from Vault directly into pods
via the Vault Agent Injector.

---

## Prerequisites

- Vault cluster is up and initialized (Vault VIP: https://vault.lab.local:8200)
- Kubernetes cluster is running (K8s API VIP: https://10.0.61.100:16443)
- FluxCD is bootstrapped and syncing
- Ansible runner is operational
- You have a Vault admin token (root or super_admin policy)

---

## Section 1: Infrastructure Setup (One-Time)

### Step 1.1 — Deploy Vault Auth Service Account via Flux

Flux will deploy the vault-auth ServiceAccount and ClusterRoleBinding automatically.

File: kubernetes/dev/deployments/infrastructure/vault/vault-auth-sa.yaml

Verify after Flux sync:
  kubectl get serviceaccount vault-auth -n kube-system
  kubectl get clusterrolebinding vault-auth

### Step 1.2 — Deploy Vault Agent Injector via Flux

Flux deploys the Vault Agent Injector via Helm chart automatically.

Files:
  kubernetes/dev/deployments/infrastructure/vault/helm-repository.yaml
  kubernetes/dev/deployments/infrastructure/vault/helm-release.yaml

Note: Ensure the vault namespace exists before Flux syncs the Helm release.
File: kubernetes/dev/deployments/infrastructure/namespaces/namespaces.yaml

Verify:
  kubectl get pods -n vault
  kubectl get deployment vault-agent-injector -n vault

### Step 1.3 — Run Vault-Kubernetes Trust Playbook

This playbook collects data from K8s and configures Vault to trust the cluster.
Run this AFTER Step 1.1 and 1.2 are confirmed working.

Playbook: ansible/dev/playbooks/k8s/integration-vault-k8s-trust.yml

  cd ansible/dev
  ansible-playbook -i inventory/inventory.ini playbooks/k8s/integration-vault-k8s-trust.yml

The playbook will:
  - Prompt for your Vault admin token (hidden input, not logged)
  - Collect K8s API endpoint, CA cert, issuer URL from k8s-master1
  - Generate a vault-auth service account token (30000h duration)
  - Enable KV-v2 secrets engine at secret/ (skips if already enabled)
  - Enable Kubernetes auth method (skips if already enabled)
  - Write the K8s trust config to Vault

Verify after playbook:
  vault read auth/kubernetes/config
  # Should show kubernetes_host, kubernetes_ca_cert, and token_reviewer_jwt_set: true

---

## Section 2: Per-Application Setup

For each new application deployed on K8s that needs Vault secrets:

### Step 2.1 — Run the App Setup Script

The script is available on vault1 at: /opt/vault/scripts/vault-pod-setup.sh
(This directory is NAS-mounted so data persists across LXC rebuilds)

The script is also tracked in the repo at: hashicorp/scripts/vault-pod-setup.sh

Login to vault1 and run:
  ./vault-pod-setup.sh

The script will prompt for:
  - Vault LDAP username
  - App name (used as the base for secret path, policy, and role names)
  - Kubernetes namespace
  - Service account name
  - One or more secret key/value pairs

What it creates in Vault:
  - Secret:  secret/<app-name>/config
  - Policy:  <app-name>-policy  (read-only access to the secret path)
  - K8s Role: <app-name>  (bound to the service account + namespace)

### Step 2.2 — Add Vault Annotations to the App Deployment

In your app deployment yaml, add the following annotations under spec.template.metadata:

  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "<app-name>"
    vault.hashicorp.com/agent-inject-secret-config.txt: "secret/data/<app-name>/config"
    vault.hashicorp.com/agent-inject-template-config.txt: |
      {{- with secret "secret/data/<app-name>/config" }}
      key1: {{ index .Data.data "key1" }}
      key2: {{ index .Data.data "key2" }}
      {{- end }}
    vault.hashicorp.com/tls-skip-verify: "false"
    vault.hashicorp.com/tls-secret: "vault-ca"
    vault.hashicorp.com/ca-cert: "/vault/tls/ca.crt"

  spec:
    serviceAccountName: <app-name>-sa

The injected secret will be available inside the pod at:
  /vault/secrets/config.txt

### Step 2.3 — Verify Injection

  kubectl exec -n <namespace> deploy/<app-name> -- cat /vault/secrets/config.txt

---

## Secret Management

To update a single key without overwriting others:
  vault kv patch secret/<app-name>/config key="new-value"

To overwrite the entire secret (all keys must be provided):
  vault kv put secret/<app-name>/config key1="val1" key2="val2"

To view current secret:
  vault kv get secret/<app-name>/config

Note: Vault Agent re-renders the secret file automatically when values change.
A pod restart is not required unless the agent cache has not expired yet.

---

## Verification Commands

  # Check Vault-K8s trust config
  vault read auth/kubernetes/config

  # List K8s roles in Vault
  vault list auth/kubernetes/role

  # Check a specific role
  vault read auth/kubernetes/role/<app-name>

  # Check Vault agent injector is running
  kubectl get pods -n vault

  # Check agent logs on a pod
  kubectl logs -n <namespace> deploy/<app-name> -c vault-agent

---
