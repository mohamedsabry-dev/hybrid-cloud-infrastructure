## Github Action trigger >> Lok for th local runner Mac Mini Personal PC >> Github Clone the repo >> Cd to the working directory >> apply terraform apply auto-approve >> Terraform first run against vspehere , get the user and password from github secrets, inject and authenticate >> then continue >> install VM and name it ansible and give it tag prod and set the specs as requested, it will be installation from nothings, so it will need some guide to let the system auto install the vm with no gui and without manual interaction >> the vm open ""How to login it now, need root pasword we configured in the first step ???or sudo -i like in ubuntu , hence our vm is rocky 10 ,, >> after we solve and login auto, run the bootstrap >>  
## have bash script to do bootstrap preprare for the golden image phase 
  - Install cloudinit , updates , wget , openssh , set admin user local and add in sudoers , also set local user named ansible_local,  give it sudo and make it passwordless configure the ip of this node and gw "if we couldnt do that via the installation " , also run the needed commands to clean the image before shutdown and get it as template ,
  - now set terraform to tell vsphere to save the template somewhere, then save the refrence link,
  - terraform go to next task or next terraform apply in sequence >> to run the anisble VM , login with user ansible_local but how while it dont have password ? and let it create key and copy its pub to placeholder, then start the creation task for the other vms and use cloud initi to inject each ip and hostname if possible with gw config , and also place the pub in the authorised file

  - ## then terraform trigger against the vm ansible and clone the repo or copy the ansible folder to there on /tmp and start operate to run the ansible playbook to setup the hostname if not done , to install ipa client on all esxcept ipa vm , and install ipa serveice on ipa vm and set up the password of the ipa but how to inject it auto ? are we encript it and put it in ansible vault or inject directly , ? i later will have vault vm , so dont want confuse myself also
  - then start the playbooks to continue the config , adding the nodes to domain, create the user super_ansible the domain user and run it without password, then validate then clean the old ansible_local user and its key and  update the inventory of anisble to use the new user super_anisble after key the ticket from domain , while run kinit will need to inject password, how to automate this ? if im creating temporary keytab to use, also while configure it or anything related to ipa i need to put the admin password 
## 


use kik start files , to set and install 





## First: >> Github Actions >> Secrets "vsphere.aws.ipadomainpassword >> AWS Account >> Limited permision >> S3 >> Dynodb >> Local Runner >> Mac Mini agent install >> Connect >> TF on Mac >> Validate Vsphere access and Data ... 
## Second: TF to vsphere to create VM ansible >> Kikstart for Ansible VM From Iso >> Bootstrap Script Validate the start and normality "install packages and updates and local username called local_ansible with no password and local username called gandalf with sudo password and sudo privilage >> bootstrap of clean before template >> Shutdown
## Third: >> TF to vsphere to to make template >> Save in NAS DS >> 
## third and half: run the anisble vm again, create key , export the pub key to tmp place 
## Forth: >> TF to vsphere to Create 10 VMs based on configuration files from the Template " and push the pub key to the all  vms during with  cloud init if possible >> Pass cloud init config file to assign each ip and hostname and gw to each vm based on configured variable matrix 
## Fifth: Now we have 11 VM , installed and have local username called ansible_local which need no password and we can login to it once via the kikstart or i shoul d push password for this user or use pub key , maybe have private and public key saved on sercrts , push both to the tf on local runner , push pup to anisble vm so tf can open conenction with it ? 
## sixth: tf >> ansible VM >> configure working directory and run the seqence of configuration playbook against the vms to set up ipa vm and ipa clients and add to domain 
## sivnth : domain up and validation , super_ansible user create over domain and get the no pass need and suod on all vms , validate test , then run the cleanup playbook to delete old local_ansible 
## How to setup domain password ? you can get it from github secrets and inject and create keytab to use each time need to run against ipa , also save the keytab locally on ansible vm where it can access it 
## in vault setup phase , we will run the needed commands , but the unseal process, the keys and root token how to get them safely 
## crrate admin users for vault, how to inject its password also , via github secrets ? 
## the deployment have full Datacenter ( Jenkins VM setup - vault setup - ansible - grafana - promethus - k8s cluster install - ipa install 


does the aws can unseal my local vault vm while no static public ip for my vault vm ? through github actions or api or anyway

Yes, AWS can help unseal your local Vault VM even without a static public IP. In fact, for security reasons, it is better that your Vault VM does not have a public IP.

The "magic" here is that the Vault VM initiates the connection outbound to AWS. As long as your Vault VM has internet access (via a NAT gateway or standard router), it can talk to AWS to get what it needs.

Here are the three ways to solve this:

1. The "Transit" Method (Most Secure/Standard)
Instead of storing unseal keys, you use AWS KMS (Key Management Service).

How it works: You configure Vault's seal "awskms" block in its config file.

The Flow: When the Vault service starts, it sends a request to AWS: "Hey, I'm authorized. Please decrypt my master key for me."

Why no Public IP is needed: The Vault VM "calls home" to AWS. AWS simply responds to that established connection. It doesn't need to "find" your VM's IP because the VM started the conversation.

2. The "Scripted AWS Secrets" Method (Easier for Home Lab)
If you don't want to use KMS, you can store your 3 unseal keys as a single secret in AWS Secrets Manager.

The Setup: You write a small Bash script on your Vault VM.

The Logic:

The script runs on boot (via systemd).

It uses the AWS CLI to fetch the secret: aws secretsmanager get-secret-value --secret-id vault/unseal-keys.

It loops through the keys and runs vault operator unseal <key>.

Security: You must ensure the VM has an IAM User (via Access Keys) or an IAM Role that is strictly limited to reading that one secret.
