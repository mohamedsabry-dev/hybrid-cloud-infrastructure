# Legacy Files

This folder contains files from the previous repository structure.

## Contents

- `DEVOPS/` - Previous DevOps configurations
- `INFRASTRUCTURE/` - Previous infrastructure documentation
- `Issues-draft.txt` - Draft issues for Linear
- `Project Tasks` - Project task tracking

## Original Phase Documentation

The original README contained phase planning documentation which has been preserved below for reference.

---

## Phase 0 - Planning

### On Local:
1. Windows 11 Pro Preparation
2. VMware Workstation
3. ESXI Master Node
4. Outer Plan VMs & Resource Allocation
   - ESXI Nested VM Prod
   - ESXI Nested VM DR
   - vCenter appliance
   - pfSense Virtual Router & FW
   - Migration Plan

### On Cloud:
1. AWS Account Setup
2. IAM Legacy Account Admin
3. Storage Setup for TF State
4. DynamoDB Setup for TF State
5. VPC Setup
6. S3 Setup
7. VPN VM Setup (OpenVPN Connect to pfSense)

### On GitHub:
1. Setup Repo "Hybrid-Cloud-Infrastructure"
2. Setup Local Runner "Mac-Mini"
3. Setup AWS Secrets & vSphere Secrets
4. Validate Integration (TF >> AWS >> Local >> GitHub >> State Management)

## Phase 1 - Core Infrastructure

### On Local:
1. Setup KickStart file
2. Setup Golden Image Template
3. Setup Ansible
4. Setup IPA
5. Setup Vault Cluster
6. Setup K8s Cluster
7. Setup Prometheus & Grafana
8. Setup Jenkins

### On Cloud:
1. Setup 2 K8s Workers
2. Setup ELB + EIP
3. Setup Identity Service
4. Setup Secret Management

## Phase 2 - Integration

1. Integrate Vault Cluster with AWS Secrets
2. Integrate IPA Domain with AWS Identity Service
3. Integrate Route53 with pfSense over OpenVPN
4. Integrate IPA <> Vault
5. Integrate Jenkins <> Ansible "Local Agent Runner"
6. Integrate IPA <> Vault <> Ansible <> Jenkins <> Mac-Mini
7. Integrate K8s Cluster with AWS K8s Public Workers
8. Integrate K8s Cluster with Internal Env Service

## Phase 3 - Applications

1. Setup dummy Apps on K8s Worker for internal use
2. Setup Dummy Apps on K8s Public Worker for public access
3. Set UP K8s Namespaces & manage overall deployment
4. Setup Terraform Pod as part of Jenkins <> K8s Integration for Internal TF Runner
5. Practice K8s Operations

## Phase 4 - Disaster Recovery

1. DR on Windows Level
2. DR on ESXI Master Level
3. DR on Outer VMs Level
4. DR as Backup Veeam Server
5. DR Switch over plan to DR Server

---

## Migration Status

These files are archived for reference. Content will be migrated to the new structure as needed.

**Note:** Do not add new content here. Use the new folder structure instead.
