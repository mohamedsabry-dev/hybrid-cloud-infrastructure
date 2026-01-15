This is Phase 0 Document
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
