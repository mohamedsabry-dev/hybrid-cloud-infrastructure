# Deployment Site - Documentation Viewer

> **Note:** This folder is entirely AI-generated and may contain inaccuracies or issues. It serves as a visual way to explore and understand the project structure.

## Purpose

This is an interactive documentation site for the Hybrid Cloud Infrastructure project. It provides:

- Visual documentation of deployment steps
- Interactive file browser (Repository Explorer)
- Live file content viewing with syntax highlighting
- IP address reference popups
- Searchable troubleshooting cases

## Usage

### Start the Documentation Server

```bash
./start-docs.sh
```

Or manually:

```bash
python3 serve-docs.py --port 9090
```

Then open: http://localhost:9090

### Features When Server is Running

- **Repository Explorer**: Browse all project files
- **File Viewer**: Click any file to view its contents with syntax highlighting
- **File Reference**: Quick access to important paths (Terraform, Ansible, Workflows)
- **Search**: Find files and documentation

### Offline Mode

The `index.html` can be opened directly in a browser for offline viewing, but file content viewing requires the server to be running.

## Files

| File | Purpose |
|------|---------|
| `index.html` | Main documentation site (~23K lines) |
| `serve-docs.py` | Python HTTP server with file content API |
| `start-docs.sh` | Easy server startup script |
| `generate-repo-explorer.py` | Regenerates the Repository Explorer tree |
| `refresh-explorer.sh` | Quick script to refresh the file tree |

## Limitations

- File paths in the static "File Reference" tab may become outdated as the repo structure changes
- The Repository Explorer is regenerated manually - run `./refresh-explorer.sh` to update
- Some documentation content may not reflect the latest project state

## Regenerating Content

To update the Repository Explorer with current file structure:

```bash
./refresh-explorer.sh
```

---

*This documentation site was generated with assistance from Claude AI.*
