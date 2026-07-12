EC2 Metadata, IAM Credential Exposure, and OIDC Runtime Risk
==============================================================

Question:
  How does an EC2 instance get its IAM credentials? What is the
  security risk with the metadata service? How does IMDSv2 fix it?
  And if you use OIDC for CI/CD, are your credentials truly safe
  during runtime?

---

How EC2 gets IAM credentials:
  When you attach an IAM role to an EC2 instance (via instance profile),
  AWS puts temporary credentials in the metadata service at:
    http://169.254.169.254/latest/meta-data/iam/security-credentials/<role-name>

  Returns live AccessKeyId, SecretAccessKey, SessionToken.
  Refreshed automatically every few hours.

  The AWS SDK checks this endpoint automatically — no .aws/credentials
  file needed, no env vars. The instance just "has" permissions.

---

The SSRF attack (IMDSv1):
  IMDSv1: plain curl, no auth. Any process can read metadata.

  Attack path:
    1. EC2 runs a web app with SSRF vulnerability
    2. Attacker sends crafted request → app fetches 169.254.169.254
    3. App returns IAM credentials to the attacker
    4. Attacker uses them from any machine — credentials are not IP-locked
    5. Attacker has whatever permissions the role allows

  Real-world: Capital One breach 2019.
    WAF on EC2 had SSRF bug + role with S3 read access.
    Attacker stole temp credentials via metadata → downloaded
    100+ million customer records from S3.

---

IMDSv2 fix:
  Two-step token-based access:
    1. PUT request to get a token (with TTL)
    2. Every request must include token in header

  Stops SSRF because most SSRF vulnerabilities can do GET but
  cannot do PUT or add custom headers. No token = no data.

  My setup: http_tokens=required in Terraform → IMDSv1 completely
  disabled. Plain curl returns nothing.

---

OIDC runtime exposure — the honest limit:

  OIDC eliminates stored credentials. But during job execution,
  temporary credentials exist in the runner's environment variables
  (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN).

  If the runner is compromised during that window:
    - Attacker has valid credentials
    - AWS doesn't know the difference — token already passed auth
    - Attacker can do anything the role allows until token expires

  OIDC doesn't eliminate the risk. It shrinks the window:

    Static keys:
      - Exposed forever until manually rotated
      - Scope: whatever the IAM user can do
      - Leaked in logs = permanent breach

    OIDC temp creds:
      - Exposed for session duration (15 min to 1 hour)
      - Scope: whatever the role allows (can be tighter)
      - After job ends: token expires automatically
      - Leaked in logs: useless after expiry

  What limits the blast radius:
    - Short TTL on STS session (1 hour max)
    - Least privilege on the role (only what Terraform needs)
    - Ephemeral runners (GitHub-hosted destroyed after job)
    - Self-hosted runners are riskier — persist between jobs,
      credentials could linger in memory

  Honest interview answer: zero-trust doesn't mean zero-risk.
  It means a breach is time-limited and scope-limited by design.
  The failure mode is bounded, not eliminated.
