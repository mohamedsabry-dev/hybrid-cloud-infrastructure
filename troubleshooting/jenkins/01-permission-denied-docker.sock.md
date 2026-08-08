# TS Case 01 — Jenkins Pipeline `docker build` Fails: "permission denied ... docker.sock" (Stale Agent Process Group Membership)

## Environment
- Jenkins controller: `jenkins-master1`
- Jenkins agent: `jenkins-agent1` (SSH-launched permanent node)
- Pipeline: `webserver` project, `docker build` stage
- `jenkins` OS user, `docker` group added via Ansible after Docker install

## Symptom
Pipeline `Build` stage fails on `docker build`, while everything else (repo checkout, Discover stage, file listing) succeeds normally:
```
+ docker build -t webserver-postgres:build-3 docker/dev/webserver/postgres
time="..." level=error msg="Can't add file .../Dockerfile to tar: io: read/write on closed pipe"
time="..." level=error msg="Can't close tar writer: io: read/write on closed pipe"
permission denied while trying to connect to the docker API at unix:///var/run/docker.sock
```

## Diagnostic Steps
1. **Confirmed `jenkins` OS user is actually in the `docker` group** — ruled out an incomplete/failed Ansible run:
   ```bash
   id jenkins
   ```
   → `groups=983(jenkins),109(docker)` — group membership correct at the file/user level.

2. **Confirmed socket ownership and permissions are correct** — ruled out a Docker daemon/install misconfiguration:
   ```bash
   ls -l /var/run/docker.sock
   ```
   → Group-owned by `docker`, group-writable as expected.

3. **Tested manually via a fresh interactive SSH session as `jenkins`** — this is the step that isolated the cause:
   ```bash
   ssh jenkins@jenkins-agent1
   docker ps
   docker build -t webserver-postgres:manual-test docker/dev/webserver/postgres
   ```
   → Both succeeded cleanly. Same user, same box, same socket, same Docker install — but working outside Jenkins' own process, while failing inside it. This ruled out permissions/socket/group-file issues entirely and pointed at something specific to the Jenkins-launched process itself.

4. **Checked how long the Jenkins agent process had been running relative to when Docker was installed.**
   → The Jenkins agent process (`agent.jar`/remoting) on `agent1` had been running continuously since **before** Docker (and the `docker` group) was ever installed on this host.

## Root Cause
Linux fixes a process's group membership at the moment the process starts — it does not re-read `/etc/group` for processes already running. The Jenkins agent process on `agent1` started before Docker was installed via Ansible, at which point the `docker` group didn't even exist yet. When Docker was later installed and `jenkins` was added to the new `docker` group, `/etc/group` was updated correctly on disk — but the already-running agent process kept using its original (pre-Docker, no-`docker`-group) membership snapshot for its entire remaining lifetime.

Any new process spawned by `jenkins` (a fresh SSH login, a manual shell) correctly picked up the current group list, which is why manual testing worked flawlessly and masked the real cause initially — the failure was specific to that one long-lived process, not the user, socket, or Docker install.

## Resolution
Rebooted `jenkins-agent1`:
```bash
sudo reboot
```
This killed the stale agent process unconditionally. Jenkins (SSH-launched node) automatically reconnected and spawned a fresh agent process on the node coming back up — this new process read current `/etc/group` and correctly included `docker`.

Re-ran the pipeline with no code changes — `docker build` succeeded.

(Lighter-weight alternative when a full reboot isn't desired: disconnect and relaunch the node from **Manage Jenkins → Nodes**, or manually `pkill -f remoting.jar` on the agent host, then relaunch — either forces a fresh process without a full OS reboot.)

## Prevention
- **General rule, not Jenkins-specific:** any time a user is added to a new group (`usermod -aG`), every already-running process for that user needs to be restarted to pick it up — updating `/etc/group` alone has no effect on processes already alive. This applies to any long-lived service, not just Jenkins agents.
- When installing Docker (or anything else that adds a user to a new group) on a host that already has a long-running Jenkins agent process, **explicitly disconnect/relaunch the node (or reboot the host) as part of that same install step** — don't assume the group change takes effect immediately just because `id <user>` shows it correctly.
- Check `jenkins-agent2` for the same latent issue if Docker was installed there via the same Ansible run while its agent process was already running — the symptom won't appear until the first `docker build` is attempted on it, so it can sit silently until it's hit mid-pipeline later.

## Cross-References
- None yet — first incident of this failure mode logged.