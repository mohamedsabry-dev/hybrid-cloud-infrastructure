Excluded from Chaos Engineering Test Plan (Out of Scope)
=========================================================

AWS / Cloud Dependencies:
- CloudWatch monitoring and alerting integration
- Lambda-based automated remediation for node failures
- CloudFormation or any AWS infrastructure-as-code
- AWS + CloudWatch + Lambda to trigger Proxmox API recovery paths
- S3 backup strategy for critical configuration data

Database:
- Multi-database MariaDB with active-standby setup
- DB failover and switchover testing between primary and standby
- Standby DB provisioning and replication

Identity / Authentication:
- IPA Domain replica deployment
- IPA failover and recovery between replicas
- Automated keytab refresh mechanism integrated with FreeIPA

Certificates:
- cert-manager deployment and testing
- Certificate expiration and rotation during failures
- TLS certificate chain verification during partial outage

Observability (as standalone scope):
- Deploy Prometheus AlertManager with full alerting rules
- Alerting pipeline end-to-end (Prometheus -> AlertManager -> Email/Slack) as a dedicated task
- CloudWatch-based monitoring
- Alerts for: node down, NFS drop, Proxmox drop, IPA down, cert expiration, etcd backup failures, Vault seal events

Automation:
- Lambda-based node failure remediation
- GitHub Actions to trigger Vault unseal auto with AWS update
- Disaster recovery runbook automation

Execution Priority Tiers:
- Tier 1/2/3 scheduling (was tied to job offer timeline, no longer relevant as structure)

Future Setup Tasks:
- Items labeled as "Not Yet Implemented" in original doc
- Items labeled as "Future topics to discuss and judge"