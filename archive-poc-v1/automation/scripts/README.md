# Scripts

> **Archived PoC v1 material** — retired infrastructure, not the current project.
> See [`../../README.md`](../../README.md) for the retirement story and the current stack.

Shell scripts for infrastructure automation and emergency procedures (PoC v1 era).

## Structure

| Folder | Language | Purpose |
|--------|----------|---------|
| `bash/` | Bash | Linux system administration |
| `powershell/` | PowerShell | Windows/VMware DR automation |

## Usage

```bash
# Run bash script
bash bash/create-emergency-user.sh

# Run PowerShell script (Windows)
.\powershell\EmergencyLabShutdown.ps1
```

## Related

- [Ansible playbooks](../ansible/)
- [Veeam emergency shutdown](../../docs/backup/02-emergency-shutdown.md)
