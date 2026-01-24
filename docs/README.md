# Project Documentation

Project-wide documentation for the hybrid cloud infrastructure.

## Structure

```
docs/
├── architecture/
│   ├── network-topology.md
│   ├── overall-design.md
│   └── diagrams/
├── phase-implementations/
│   ├── phase-00-planning.md
│   ├── phase-01-devops-foundation.md
│   └── ...
└── project-overview.md
```

## Quick Links

### Architecture
- [Network Topology](architecture/network-topology.md)
- [Overall Design](architecture/overall-design.md)
- [Diagrams](architecture/diagrams/)

### Phase Tracking
- [Phase 0: Planning](phase-implementations/phase-00-planning.md)
- [Phase 1: DevOps Foundation](phase-implementations/phase-01-devops-foundation.md)

### Standards
- [Naming Conventions](../shared/docs/standards/naming-conventions.md)
- [Tagging Strategy](../shared/docs/standards/tagging-strategy.md)

## Service-Specific Docs

Each service has its own docs folder:
- [AWS Docs](../aws/docs/)
- [VMware Docs](../vmware/docs/)
- [Kubernetes Docs](../kubernetes/docs/)
- etc.
