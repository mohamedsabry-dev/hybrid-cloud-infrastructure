Skill 4 — AWS (12 questions)
=============================

Format: Standard questions only. Project examples are ammunition
you inject into answers to bait follow-ups — not separate questions.
Your VPC design, WireGuard tunnel, OIDC federation, KMS unseal chain,
etcd-backup IAM chain, Terraform backend bootstrap — inject when natural.

---

1. Tell me what you know about AWS networking.

   Coverage check:
   - VPC, subnets (public vs private), route tables
   - IGW (1:1 NAT for public IPs), NAT Gateway (PAT for private subnets)
   - Security groups (stateful, allow-only, instance level)
   - NACLs (stateless, allow+deny, subnet level, rule ordering)
   - VPC endpoints (gateway vs interface, avoiding NAT costs)
   - VPC peering, VPC Flow Logs
   - Route53 (hosted zones, record types, routing policies, alias vs CNAME)
   - AWS Network Firewall (VPC-level, where it sits in the packet path)

2. An EC2 can't reach the internet — troubleshoot.

   Coverage check:
   - OS routing table first (kernel decides before AWS sees it)
   - does instance have a public IP / EIP?
   - subnet route table — route to 0.0.0.0/0, next hop IGW or NAT GW?
   - IGW attached to VPC?
   - NACL outbound + inbound return (stateless — both directions)
   - SG outbound rules
   - DNS resolution (VPC resolver at .2)
   - Network Firewall if deployed
   - try multiple targets (8.8.8.8, 1.1.1.1)

3. Explain IAM — users, roles, policies, assume role, STS.

   Coverage check:
   - authentication (proving identity) vs authorization (what you can do)
   - IAM user — long-lived credentials, for humans or legacy service accounts
   - IAM role — no permanent credentials, assumed temporarily
   - IAM policy — JSON document, allow/deny actions on resources
   - identity-based vs resource-based policies
   - STS AssumeRole flow — request → validate trust policy → temp creds returned
   - temporary credentials (AccessKeyId + SecretAccessKey + SessionToken, default 1hr)
   - least privilege principle
   - SCPs (Service Control Policies) in AWS Organizations

4. What is OIDC federation and when would you use it?

   Coverage check:
   - eliminating long-lived credentials for CI/CD
   - identity provider trust (GitHub, GitLab as IdP)
   - JWT token — claims (sub, aud, iss)
   - AssumeRoleWithWebIdentity — STS validates JWT against IdP
   - trust policy on the role (conditions: repo, branch, environment)
   - token validation checks (issuer, audience, signature, expiry)

5. How do you securely manage secrets in AWS?

   Coverage check:
   - AWS Secrets Manager (rotation, versioning, cross-account access)
   - KMS (customer managed keys vs AWS managed)
   - envelope encryption (data key encrypts data, KMS key encrypts data key)
   - key policies (key administrators vs key users — separate permissions)
   - encryption at rest (S3, EBS, RDS — all use KMS)
   - when to use Secrets Manager vs Parameter Store vs KMS directly

6. An EC2 is unreachable via SSH — troubleshoot.

   Coverage check:
   - SG inbound port 22 open to your IP?
   - NACL inbound 22 + outbound ephemeral ports
   - subnet route table (can traffic reach the instance?)
   - instance has public IP or you're routing through VPN/bastion?
   - correct key pair (.pem permissions, right user: ec2-user/ubuntu)
   - instance state (running? status checks passing?)
   - OS-level firewall (iptables, ufw)
   - disk full preventing login
   - EC2 serial console as last resort

7. What is EC2 instance metadata? IMDSv2 — why does it matter?

   Coverage check:
   - metadata service at 169.254.169.254
   - what it exposes (instance ID, IAM role credentials, user data, network info)
   - IMDSv1 — simple GET request, vulnerable to SSRF attacks
   - IMDSv2 — requires PUT to get session token first, then GET with token header
   - hop limit (default 1 — prevents containers/nested VMs from reaching metadata)
   - how SSRF exploits work against IMDSv1 (attacker tricks app into requesting creds)
   - enforcing IMDSv2 via launch template or instance metadata options

8. How does storage work on AWS — EBS, EFS, S3?

   Coverage check:
   - EBS — block storage, attached to one instance, volume types (gp3, io2, st1)
   - EBS snapshots, encryption, lifecycle
   - EFS — file storage (NFS), shared across instances, elastic sizing
   - S3 — object storage, buckets, unlimited scale
   - S3 storage classes (Standard, IA, One Zone-IA, Glacier, Deep Archive)
   - S3 lifecycle policies, versioning, replication
   - bucket policy vs IAM policy (resource-based vs identity-based)
   - S3 presigned URLs
   - when to pick each (block for OS/DB, file for shared access, object for backups/static)

9. CloudWatch vs CloudTrail — what's the difference?

   Coverage check:
   - CloudWatch — metrics, alarms, logs, log insights, dashboards
   - custom metrics, metric math
   - CloudWatch Logs agent vs unified agent
   - CloudTrail — API audit trail, who did what when
   - management events vs data events
   - VPC Flow Logs — what they capture (accepted/rejected, ENI/subnet/VPC level)
   - when to use each (performance monitoring vs security auditing vs network debugging)

10. What are load balancers on AWS and how does Auto Scaling work?

    Coverage check:
    - ALB (L7 — HTTP/HTTPS, path/host routing, WAF integration)
    - NLB (L4 — TCP/UDP, static IP, ultra-low latency)
    - CLB (legacy — avoid for new workloads)
    - target groups, listener rules, health checks
    - connection draining, sticky sessions
    - Auto Scaling — launch templates, desired/min/max capacity
    - scaling policies (target tracking, step, scheduled)
    - cooldown periods
    - how ASG integrates with ALB health checks

11. What is RDS and when would you use it?

    Coverage check:
    - managed database service — patching, backups, failover handled by AWS
    - Multi-AZ — synchronous standby replica, automatic failover, same endpoint
    - Read Replica — asynchronous, for read scaling, separate endpoint
    - supported engines (MySQL, PostgreSQL, MariaDB, Oracle, SQL Server)
    - parameter groups, option groups
    - automated backups, manual snapshots, point-in-time recovery
    - when RDS vs self-managed on EC2 (control vs convenience tradeoff)

12. How do you manage infrastructure as code on AWS?

    Coverage check:
    - Terraform backend — S3 bucket + DynamoDB for state locking
    - bootstrap chicken-and-egg (backend doesn't exist yet when you first run)
    - state locking — prevents concurrent applies
    - OIDC credential expiry on long runs (1-hour STS token timeout)
    - orphaned state locks — how to identify and resolve
    - CloudFormation awareness (AWS-native, stack-based, drift detection)
    - why Terraform over CloudFormation for multi-cloud / hybrid
