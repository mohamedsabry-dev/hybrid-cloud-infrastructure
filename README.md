This is Phase 0 Document " 
## We have to setup the following

A. On Local: 
1. Windows 11 Pro Preparation 
2. VMware Workstation
3. ESXI Master Node
4. Outter Plan VMs & Resource Allocation
    4.a ESXI Nested VM Prod
    4.b ESXI Nested VM DR
    4.c Vcenter appliance
    4.d Pfsense Virtual Router & FW
    5.e Migration Plan


B. On Cloud: 
1. AWS Account Setup
2. IAM Legacy Account Admin
3. Storage Setup for TF State
4. Dynamodb Setup for TF State
5. VPC Setup
6. S3 Setup
7. VPN VM Setup << OpenVPN Connect to Pfsense >>


C. On GitHub
1. Setup Repo "Hybrid-Cloud-Infrastructure"
2. Setup Local Runner "Mac-Mini"
3. Setup AWS Secrets & Phsere Secrets
4. Validate The Integration ((TF >> AWS >> Local >> Github >> State Managemnt))


This is Phase 1 Document
## We have to setup the following

A. On Local:
1. Setup KickStart file
2. Setup Golden Image Template
3. Setup Ansible 
4. Setup IPA
5. Setup Vault Cluster
6. Setup K8s Cluster
7. Setup Promethus & Grafana
8. Setup Jenkins 

B. On Cloud:
1. Setup 2 K8s Worker 
2. Setup ELB + EIP
3. Setup Identity Service
4. Setup Secret Managment 


This is Phase 2 Document
## We have to setup the following

A. On Local & Cloud Together: 
1. Integrate Vault Cluster with AWS Secrets 
2. Integrate IPA Domain with AWS Identity Service
3. Integrate Route53 with Pfsense over openVPN
4. Integrate IPA <<>> Vault 
5. Integrate Jenkins <<>> Ansible "Local Agent Runner"
6. Integrate IPA <> Vault <> Ansible <> Jenkins <> Mac-Mini 
7. Integrate K8s Cluster with AWS K8s Public Workers
8. Integrate K8s Cluster with Internal Env Service


This is Phase 3 Document
## We have to setup the following

1. Setup dummy Apps on K8s Worker for internal use 
2. Setup Dummy Apps on K8s Public Worker for public access 
3. Set UP K8s Namespaces & manager overall deployment
4. Setup Terraform Pod as part of jenkins <> K8s Integratoon for Internal TF Runner
5. Practice K8s Operations


This is Phase 4 Document
## We have to setup the following

1. DR on Windows Level 
2. DR on ESXI Master Level
3. DR on Outter VMs Level
4. DR as Backup Veeam Server
5. DR Switch over plan to DR Server
