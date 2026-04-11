# Roadmap

> Draft ideas and future directions for the hybrid cloud infrastructure. Not formal tasks - just thinking ahead.

---

## Integrate New Tools with Current Infrastructure

The infrastructure is designed as a "stadium" - ready to host any workload. Here's the sequence for quickly involving any new tool:

1. **Provision** - Follow existing Terraform patterns for LXC or VM, trigger new resources via golden image
2. **Domain Join** - Run playbooks 1, 2, 3, 4 to add to FreeIPA domain
3. **Network** - No changes needed. Already have 6 VLANs per environment (x0-x5) covering:
   - Management
   - Worker
   - Master
   - Secrets
   - External/Nginx
   - Identity
4. **IP Assignment** - Just get new IP via Terraform and engage
5. **Initial Config** - Ansible playbook for quick basic fixes and overcoming LXC limitations

This preset makes the environment a true stadium, not just a static project.

---

## AWS Monitoring & Self-Healing

- **CloudWatch** integration for centralized monitoring
- **Lambda** functions for self-healing actions
- Potential triggers: resource alerts, backup failures, threshold breaches

---

## Network Hardening

- Enhance network isolation at nodes level and router
- Enable firewall rules
- Close unnecessary opened ports
- Review and tighten security groups

---

## Future: EKS on AWS

- Add managed Kubernetes (EKS) as another environment
- Considerations:
  - Cost implications - need to evaluate
  - Time investment for re-setup
  - Can judge later based on learning needs and job requirements

---

## Disaster Recovery Expansion

- Simulate additional DR scenarios
- Reference: `disaster-recovery/ROADMAP.md` for detailed test cases
- Continue building confidence in recovery procedures

---

*Last updated: April 12, 2026*
