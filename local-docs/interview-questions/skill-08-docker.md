Skill 8 — Docker (6 questions)
===============================

Format: Standard questions only. Project examples are ammunition.
Your remediation pod image, etcd-backup container, GHCR workflow,
branch-based tagging (latest vs dev), multi-stage builds, Flux
image automation — inject when the bridge is earned.

---

1. What is a container and how does it differ from a VM?

   Coverage check:
   - containers share host kernel (namespaces + cgroups for isolation)
   - VMs have full OS with hypervisor
   - namespaces (pid, net, mnt, uts, ipc, user) — what each isolates
   - cgroups — resource limits (CPU, memory)
   - overhead comparison (startup time, resource usage)
   - security boundary differences (container escape vs VM escape)
   - when to use containers vs VMs

2. How do you build a Docker image — Dockerfile, layers, optimization?

   Coverage check:
   - Dockerfile instructions (FROM, COPY vs ADD, RUN, CMD vs ENTRYPOINT)
   - ARG vs ENV
   - layer caching — order matters (least-changing first)
   - multi-stage builds (build stage vs runtime stage, smaller final image)
   - .dockerignore
   - image size optimization (alpine/distroless bases, combining RUN commands)
   - union filesystem, copy-on-write layers
   - dangling images, docker image prune

3. How does Docker networking work?

   Coverage check:
   - bridge network (default, container-to-container via DNS)
   - host network (container uses host's network stack directly)
   - none (no networking)
   - custom networks (isolation, DNS resolution by container name)
   - port mapping (-p host:container)
   - overlay network (multi-host, Swarm/K8s)

4. A container keeps restarting. How do you debug it?

   Coverage check:
   - docker logs (check stdout/stderr)
   - docker inspect (exit code, state, config)
   - docker exec (if container stays up long enough)
   - docker stats (resource usage)
   - docker events (lifecycle events)
   - restart policies (no, always, on-failure, unless-stopped)
   - resource limits (--memory, --cpus) — OOMKilled?
   - common causes (missing env vars, wrong CMD, permission denied, port conflict)

5. How do you manage container storage — volumes and bind mounts?

   Coverage check:
   - volumes (managed by Docker, persist after container removal)
   - bind mounts (map host directory into container)
   - tmpfs (in-memory, ephemeral)
   - named volumes vs anonymous volumes
   - when to use volume vs bind mount
   - data persistence patterns
   - Docker Compose volume definitions

6. How do you manage and distribute container images?

   Coverage check:
   - container registries (Docker Hub, GHCR, ECR, Harbor)
   - push/pull workflow
   - tagging strategies (semver, latest, commit SHA, branch-based)
   - image scanning for vulnerabilities (Trivy, Snyk, Docker Scout)
   - authentication to registries (docker login, CI/CD tokens)
   - running as non-root user
   - read-only filesystem
   - dropping capabilities
   - image cleanup and retention policies
