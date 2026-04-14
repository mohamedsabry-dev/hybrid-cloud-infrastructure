# Vault AWS KMS Auto-Unseal Dependency
# Date: 2026-04-13
# Result: PASS

---

## Scope

Test what happens when AWS KMS credentials are missing:
- Does vault start?
- Does vault stay sealed or fail completely?
- Impact on cluster with 2/3 nodes still healthy
- Recovery procedure

---

## Setup Overview

Vault uses AWS KMS for auto-unseal. Credentials flow:

```
AWS Secrets Manager -> GitHub Actions -> Ansible -> /etc/vault.d/vault.env -> systemd
```

**Discovery Commands (if setup unknown):**

```bash
# Check seal configuration
cat /etc/vault.d/vault.hcl | grep -A10 'seal'

# Check where credentials come from
systemctl show vault | grep -i environment

# View credentials file (if exists)
cat /etc/vault.d/vault.env
```

**Current Configuration:**

```bash
[root@vault1 ~]# cat /etc/vault.d/vault.hcl | grep -A10 'seal'
seal "awskms" {
  region     = "us-east-1"
  kms_key_id = "alias/vault-unseal"
}

[root@vault1 ~]# systemctl show vault | grep -i environment
EnvironmentFiles=/etc/vault.d/vault.env (ignore_errors=no)
```

**Credentials Location:** `/etc/vault.d/vault.env` (mode 0600, owner vault)
- Contains: `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
- Loaded by systemd on vault service start

---

## Pre-Test State

**Timestamp:** 2026-04-13 01:25 EET

```bash
[root@vault1 ~]# vault status | grep -i seal
Seal Type                awskms
Recovery Seal Type       shamir
Sealed                   false
```

---

## Test Execution

**Action:** Break AWS credentials on vault1

```bash
[root@vault1 vault.d]# cp vault.env vault.env.backup
[root@vault1 vault.d]# echo "# BROKEN FOR DR TEST" > vault.env
[root@vault1 vault.d]# cat /etc/vault.d/vault.env
# BROKEN FOR DR TEST

[root@vault1 vault.d]# systemctl restart vault
Job for vault.service failed because the control process exited with error code.
See "systemctl status vault.service" and "journalctl -xeu vault.service" for details.

[root@vault1 vault.d]# vault status
Error checking seal status: Get "https://vault1.lab.local:8200/v1/sys/seal-status":
dial tcp 10.0.62.10:8200: connect: connection refused
```

**Time:** 2026-04-13 01:30 EET

**Cluster Status (from vault3):**
```bash
[root@vault3 ~]# vault operator raft autopilot state
Healthy:                         false        <- Degraded (vault1 down)
Failure Tolerance:               0            <- Can't lose another node
Leader:                          vault3
Servers:
   vault1
      Healthy:           false               <- SERVICE FAILED TO START

   vault2
      Healthy:           true                <- Still healthy

   vault3
      Status:            leader              <- Still leader
      Healthy:           true

[root@vault3 ~]# vault status
Sealed                   false               <- Cluster still unsealed!
HA Mode                  active
```

**Key Difference from Quorum Loss Test:**
- Quorum loss: Killed 2 nodes -> lost quorum -> new pods STUCK
- AWS KMS: Killed 1 node -> 2/3 quorum -> new pods CAN get secrets!

**New Pod Test (while vault1 down):**
```bash
[root@k8s-master1 ~]# kubectl scale deployment wordpress -n apps --replicas=4
deployment.apps/wordpress scaled

[root@k8s-master1 ~]# kubectl get pods -n apps -o wide -w
NAME                         READY   STATUS     AGE
wordpress-6d5cdf8c64-4rtg9   0/2     Init:0/2   1s    <- New pod
wordpress-6d5cdf8c64-4rtg9   0/2     Init:1/2   2s    <- wait-for-mariadb passed
wordpress-6d5cdf8c64-4rtg9   1/2     Running    5s    <- vault-agent-init passed!
wordpress-6d5cdf8c64-4rtg9   2/2     Running    11s   <- FULLY READY
```

**New pod got secrets in 11 seconds** even with vault1 down!

| Check | Result | Evidence |
|-------|--------|----------|
| Vault1 fails to start | **YES** | Service failed, connection refused |
| Cluster still operational | **YES** | vault2+vault3 = 2/3 quorum |
| New pods CAN get secrets | **YES** | Pod ready in 11s |
| Apps unaffected | **YES** | WordPress serving normally |

---

## Failure Logs (journalctl)

```bash
# AWS KMS failure - no credentials
Apr 13 01:31:27 vault1 vault[1376]: error parsing Seal configuration: error fetching AWS KMS wrapping key information: NoCredentialProviders: no valid providers in chain. Deprecated.
Apr 13 01:31:27 vault1 vault[1376]:         For verbose messaging see aws.Config.CredentialsChainVerboseErrors
Apr 13 01:31:27 vault1 systemd[1]: vault.service: Main process exited, code=exited, status=1/FAILURE
Apr 13 01:31:27 vault1 systemd[1]: Failed to start vault.service - "HashiCorp Vault - A tool for managing secrets".

# Systemd retry attempts (3x then give up)
Apr 13 01:31:32 vault1 systemd[1]: vault.service: Scheduled restart job, restart counter is at 1.
Apr 13 01:31:33 vault1 vault[1392]: error parsing Seal configuration: error fetching AWS KMS wrapping key information: NoCredentialProviders
Apr 13 01:31:38 vault1 systemd[1]: vault.service: Scheduled restart job, restart counter is at 2.
Apr 13 01:31:38 vault1 vault[1408]: error parsing Seal configuration: error fetching AWS KMS wrapping key information: NoCredentialProviders
Apr 13 01:31:44 vault1 systemd[1]: vault.service: Scheduled restart job, restart counter is at 3.
Apr 13 01:31:44 vault1 systemd[1]: vault.service: Start request repeated too quickly.
Apr 13 01:31:44 vault1 systemd[1]: Failed to start vault.service - "HashiCorp Vault - A tool for managing secrets".
```

**Key Finding:** Without AWS credentials, vault won't start at all (not just sealed - service fails). Systemd retries 3x then gives up.

---

## Recovery

**Action:** Restore AWS credentials

```bash
[root@vault1 vault.d]# rm vault.env
rm: remove regular file 'vault.env'? y

[root@vault1 vault.d]# mv vault.env.backup vault.env

[root@vault1 vault.d]# systemctl restart vault

[root@vault1 vault.d]# vault status
Key                      Value
---                      -----
Seal Type                awskms
Recovery Seal Type       shamir
Initialized              true
Sealed                   false              <- AUTO-UNSEALED!
HA Mode                  standby
Active Node Address      https://10.0.62.12:8200
```

**Time:** 2026-04-13 01:34 EET

**Recovery Logs (journalctl):**
```bash
Apr 13 01:34:24 vault1 systemd[1]: Starting vault.service - "HashiCorp Vault - A tool for managing secrets"...
Apr 13 01:34:25 vault1 vault[1587]: ==> Vault server configuration:
Apr 13 01:34:25 vault1 vault[1587]:    Environment Variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, ...  <- Credentials loaded!
Apr 13 01:34:25 vault1 vault[1587]: 2026-04-13T01:34:25.452+0200 [INFO]  core: stored unseal keys supported, attempting fetch
Apr 13 01:34:25 vault1 vault[1587]: 2026-04-13T01:34:25.861+0200 [INFO]  core: vault is unsealed
Apr 13 01:34:25 vault1 vault[1587]: 2026-04-13T01:34:25.861+0200 [INFO]  core: unsealed with stored key  <- AWS KMS auto-unseal worked!
Apr 13 01:34:25 vault1 vault[1587]: 2026-04-13T01:34:25.861+0200 [INFO]  core: entering standby mode
Apr 13 01:34:25 vault1 vault[1587]: 2026-04-13T01:34:25.861+0200 [INFO]  storage.raft: entering follower state
Apr 13 01:34:25 vault1 systemd[1]: Started vault.service - "HashiCorp Vault - A tool for managing secrets".
```

**Cluster Fully Restored:**
```bash
[root@vault1 vault.d]# vault operator raft list-peers
Node      Address            State       Voter
----      -------            -----       -----
vault1    10.0.62.10:8201    follower    true     <- Back online!
vault2    10.0.62.11:8201    follower    true
vault3    10.0.62.12:8201    leader      true

[root@vault1 vault.d]# vault operator raft autopilot state
Healthy:                         true         <- Cluster healthy!
Failure Tolerance:               1            <- Can lose 1 node
Leader:                          vault3
Servers:
   vault1    Healthy: true    Last Contact: 3.5s
   vault2    Healthy: true    Last Contact: 1.9s
   vault3    Healthy: true    (leader)
```

| Check | Result | Evidence |
|-------|--------|----------|
| Auto-unseal succeeds on restart | **YES** | `core: unsealed with stored key` |
| Vault cluster healthy | **YES** | `Healthy: true`, `Failure Tolerance: 1` |
| vault1 rejoined cluster | **YES** | Shows as follower in raft peers |

---

## Summary

| Phase | Time | Result |
|-------|------|--------|
| Break credentials | 01:31 | vault1 failed to start (NoCredentialProviders) |
| Cluster impact | - | 2/3 quorum maintained, apps unaffected |
| New pod test | - | Pod got secrets in 11s (vault2/3 healthy) |
| Restore credentials | 01:34 | vault1 auto-unsealed, rejoined cluster |

---

## Key Findings

1. Without AWS credentials, vault **cannot start at all** (not just sealed - service fails)
2. Error is clear: `NoCredentialProviders: no valid providers in chain`
3. Systemd retries 3x then gives up
4. 2/3 quorum maintained - apps unaffected during single node failure
5. Restoring credentials -> auto-unseal works immediately

---

## Recovery Procedure

1. Restore `/etc/vault.d/vault.env` with valid AWS credentials
2. Run `systemctl restart vault`
3. Verify with `vault status` - should show `Sealed: false`
4. Confirm cluster health with `vault operator raft autopilot state`

---

## Recommendation

**Backup AWS credentials** - Keep vault.env accessible for emergencies:
- Store in password manager
- Keep encrypted backup on NAS
- Document in runbook

---

## Result: PASS

- AWS KMS is hard dependency (no creds = no start)
- 2/3 quorum maintained cluster health
- Recovery is simple: restore creds + restart
- Duration: ~3 minutes
