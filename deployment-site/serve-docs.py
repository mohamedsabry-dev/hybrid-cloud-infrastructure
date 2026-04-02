#!/usr/bin/env python3
"""
=============================================================================
HYBRID CLOUD INFRASTRUCTURE - INTERACTIVE DOCUMENTATION SERVER
=============================================================================

A lightweight local web server that serves the documentation site with
full file content viewing capabilities.

Features:
- Browse entire repository structure
- View any file content with syntax highlighting
- Search across file contents
- Real-time - always shows current state
- No external dependencies (uses Python stdlib)

Usage:
    python3 serve-docs.py [--port 8080]

Then open: http://localhost:8080

Author: Hybrid Cloud Infrastructure
=============================================================================
"""

import os
import sys
import json
import mimetypes
import argparse
import fnmatch
import re
from pathlib import Path
from http.server import HTTPServer, SimpleHTTPRequestHandler
from urllib.parse import urlparse, parse_qs, unquote
from datetime import datetime

# =============================================================================
# CONFIGURATION
# =============================================================================

# Get the repository root (parent of deployment-site)
SCRIPT_DIR = Path(__file__).parent.absolute()
REPO_ROOT = SCRIPT_DIR.parent

# Security: Files/patterns to NEVER serve content for
BLOCKED_PATTERNS = [
    "*.tfvars",
    "*.tfvars.json",
    "*.tfstate",
    "*.tfstate.*",
    ".terraform/*",
    "key*",
    "Key*",
    "*.pem",
    "*.key",
    "*.crt",
    "id_rsa*",
    "id_ed25519*",
    ".ansible_vault",
    "*vault_password*",
    "network/**/backups/*.cfg",
    "network/router/mikrotik/backups/**",
    "*.bin",
    "*.rsc",
    ".env",
    ".env.*",
    "*.env",
    ".git/*",
    "node_modules/*",
    "__pycache__/*",
    "*.pyc",
]

# File extensions for syntax highlighting (maps to highlight.js language)
SYNTAX_MAP = {
    ".tf": "terraform",
    ".hcl": "terraform",
    ".yml": "yaml",
    ".yaml": "yaml",
    ".j2": "jinja2",
    ".sh": "bash",
    ".bash": "bash",
    ".py": "python",
    ".js": "javascript",
    ".json": "json",
    ".html": "html",
    ".css": "css",
    ".md": "markdown",
    ".xml": "xml",
    ".sql": "sql",
    ".go": "go",
    ".rs": "rust",
    ".toml": "toml",
    ".ini": "ini",
    ".conf": "nginx",
    ".cfg": "ini",
    ".txt": "plaintext",
    "Dockerfile": "dockerfile",
    "Makefile": "makefile",
}

# File type icons and colors (matches the generator)
FILE_TYPES = {
    ".tf": {"icon": "⬡", "color": "#844FBA", "label": "Terraform"},
    ".yml": {"icon": "📋", "color": "#E34F26", "label": "YAML"},
    ".yaml": {"icon": "📋", "color": "#E34F26", "label": "YAML"},
    ".j2": {"icon": "🔧", "color": "#B41717", "label": "Jinja2"},
    ".sh": {"icon": "⚡", "color": "#4EAA25", "label": "Shell"},
    ".py": {"icon": "🐍", "color": "#3776AB", "label": "Python"},
    ".md": {"icon": "📖", "color": "#083FA1", "label": "Markdown"},
    ".txt": {"icon": "📝", "color": "#6E7681", "label": "Text"},
    ".json": {"icon": "📦", "color": "#000000", "label": "JSON"},
    ".html": {"icon": "🌐", "color": "#E44D26", "label": "HTML"},
    ".css": {"icon": "🎨", "color": "#264DE4", "label": "CSS"},
    ".js": {"icon": "📜", "color": "#F7DF1E", "label": "JavaScript"},
    "default": {"icon": "📄", "color": "#6E7681", "label": "File"},
}

# =============================================================================
# SECURITY HELPERS
# =============================================================================

def is_blocked(path: str) -> bool:
    """Check if a file path matches any blocked pattern."""
    path_str = str(path)
    name = os.path.basename(path_str)

    for pattern in BLOCKED_PATTERNS:
        if '**' in pattern:
            # Convert ** glob to regex
            regex = pattern.replace('**', '.*').replace('*', '[^/]*')
            if re.match(regex, path_str):
                return True
        elif fnmatch.fnmatch(name, pattern):
            return True
        elif fnmatch.fnmatch(path_str, pattern):
            return True

    return False


def is_binary(file_path: Path) -> bool:
    """Check if a file is binary."""
    try:
        with open(file_path, 'rb') as f:
            chunk = f.read(8192)
            if b'\x00' in chunk:
                return True
            # Check for high ratio of non-text characters
            text_chars = bytearray({7,8,9,10,12,13,27} | set(range(0x20, 0x100)) - {0x7f})
            non_text = sum(1 for byte in chunk if byte not in text_chars)
            if len(chunk) > 0 and non_text / len(chunk) > 0.30:
                return True
    except:
        return True
    return False


# =============================================================================
# FILE SYSTEM HELPERS
# =============================================================================

def get_file_info(path: Path, relative_to: Path) -> dict:
    """Get file information."""
    try:
        stat = path.stat()
        rel_path = str(path.relative_to(relative_to))
        ext = path.suffix.lower()
        file_type = FILE_TYPES.get(ext, FILE_TYPES["default"])

        # Format size
        size = stat.st_size
        if size < 1024:
            size_str = f"{size} B"
        elif size < 1024 * 1024:
            size_str = f"{size/1024:.1f} KB"
        else:
            size_str = f"{size/1024/1024:.1f} MB"

        return {
            "name": path.name,
            "path": rel_path,
            "type": "file",
            "size": stat.st_size,
            "size_formatted": size_str,
            "modified": datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d %H:%M"),
            "extension": ext,
            "icon": file_type["icon"],
            "color": file_type["color"],
            "label": file_type["label"],
            "syntax": SYNTAX_MAP.get(ext, SYNTAX_MAP.get(path.name, "plaintext")),
            "is_binary": is_binary(path),
            "is_blocked": is_blocked(rel_path),
        }
    except Exception as e:
        return {"error": str(e)}


def get_folder_info(path: Path, relative_to: Path) -> dict:
    """Get folder information."""
    try:
        rel_path = str(path.relative_to(relative_to))
        if rel_path == '.':
            rel_path = ''

        return {
            "name": path.name or "hybrid-cloud-infrastructure",
            "path": rel_path,
            "type": "directory",
        }
    except Exception as e:
        return {"error": str(e)}


def scan_directory(path: Path, relative_to: Path = None, max_depth: int = 10, current_depth: int = 0) -> list:
    """Scan a directory and return its contents."""
    if relative_to is None:
        relative_to = path

    if current_depth > max_depth:
        return []

    items = []

    try:
        entries = sorted(path.iterdir(), key=lambda x: (x.is_file(), x.name.lower()))

        for entry in entries:
            rel_path = str(entry.relative_to(relative_to))

            # Skip hidden files and blocked patterns
            if entry.name.startswith('.') and entry.name not in ['.github']:
                continue
            if is_blocked(rel_path):
                continue

            if entry.is_dir():
                folder_info = get_folder_info(entry, relative_to)
                folder_info["children"] = scan_directory(entry, relative_to, max_depth, current_depth + 1)
                # Skip empty folders
                if folder_info["children"] or current_depth == 0:
                    items.append(folder_info)
            else:
                file_info = get_file_info(entry, relative_to)
                if not file_info.get("is_blocked"):
                    items.append(file_info)

    except PermissionError:
        pass

    return items


def read_file_content(file_path: Path) -> dict:
    """Read file content safely."""
    rel_path = str(file_path.relative_to(REPO_ROOT))

    # Security check
    if is_blocked(rel_path):
        return {
            "error": "Access denied",
            "message": "This file contains sensitive information and cannot be displayed.",
            "path": rel_path,
        }

    # Check if file exists
    if not file_path.exists():
        return {
            "error": "Not found",
            "message": f"File not found: {rel_path}",
            "path": rel_path,
        }

    # Check if binary
    if is_binary(file_path):
        return {
            "error": "Binary file",
            "message": "This is a binary file and cannot be displayed as text.",
            "path": rel_path,
            "size": file_path.stat().st_size,
        }

    # Read content
    try:
        with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()

        # Get file info
        info = get_file_info(file_path, REPO_ROOT)

        return {
            "success": True,
            "path": rel_path,
            "name": file_path.name,
            "content": content,
            "lines": content.count('\n') + 1,
            "size": info.get("size_formatted", "N/A"),
            "modified": info.get("modified", "N/A"),
            "syntax": info.get("syntax", "plaintext"),
            "icon": info.get("icon", "📄"),
            "color": info.get("color", "#6E7681"),
            "label": info.get("label", "File"),
        }

    except Exception as e:
        return {
            "error": "Read error",
            "message": str(e),
            "path": rel_path,
        }


def search_files(query: str, search_content: bool = False) -> list:
    """Search for files by name or content."""
    results = []
    query_lower = query.lower()

    for root, dirs, files in os.walk(REPO_ROOT):
        # Skip hidden and blocked directories
        dirs[:] = [d for d in dirs if not d.startswith('.') and d not in ['node_modules', '__pycache__', '.terraform', 'venv', '.venv']]

        for file in files:
            file_path = Path(root) / file
            rel_path = str(file_path.relative_to(REPO_ROOT))

            if is_blocked(rel_path):
                continue

            # Search in filename
            name_match = query_lower in file.lower()
            path_match = query_lower in rel_path.lower()
            content_match = False
            content_preview = ""

            # Search in content if requested
            if search_content and not is_binary(file_path):
                try:
                    with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                        content = f.read()
                        if query_lower in content.lower():
                            content_match = True
                            # Find context around match
                            idx = content.lower().find(query_lower)
                            start = max(0, idx - 50)
                            end = min(len(content), idx + len(query) + 50)
                            content_preview = "..." + content[start:end].replace('\n', ' ') + "..."
                except:
                    pass

            if name_match or path_match or content_match:
                info = get_file_info(file_path, REPO_ROOT)
                info["name_match"] = name_match
                info["path_match"] = path_match
                info["content_match"] = content_match
                info["content_preview"] = content_preview
                results.append(info)

                if len(results) >= 100:
                    return results

    return results


# =============================================================================
# HTTP REQUEST HANDLER
# =============================================================================

class DocsHandler(SimpleHTTPRequestHandler):
    """Custom HTTP handler for serving documentation with API endpoints."""

    def __init__(self, *args, **kwargs):
        # Set the directory to serve static files from
        super().__init__(*args, directory=str(SCRIPT_DIR), **kwargs)

    def do_GET(self):
        """Handle GET requests."""
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)

        # API endpoints
        if path == '/api/tree':
            self.send_json_response(scan_directory(REPO_ROOT, REPO_ROOT))

        elif path == '/api/file':
            file_path = query.get('path', [''])[0]
            if file_path:
                full_path = REPO_ROOT / unquote(file_path)
                # Security: ensure path is within repo
                try:
                    full_path.relative_to(REPO_ROOT)
                    self.send_json_response(read_file_content(full_path))
                except ValueError:
                    self.send_json_response({"error": "Invalid path"})
            else:
                self.send_json_response({"error": "No path specified"})

        elif path == '/api/search':
            q = query.get('q', [''])[0]
            search_content = query.get('content', ['false'])[0].lower() == 'true'
            if q and len(q) >= 2:
                self.send_json_response(search_files(q, search_content))
            else:
                self.send_json_response([])

        elif path == '/api/info':
            self.send_json_response({
                "repo_root": str(REPO_ROOT),
                "server_time": datetime.now().isoformat(),
                "version": "1.0.0",
            })

        # Serve index.html for root
        elif path == '/' or path == '/index.html':
            self.path = '/index.html'
            super().do_GET()

        # Serve static files
        else:
            super().do_GET()

    def send_json_response(self, data):
        """Send a JSON response."""
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data, ensure_ascii=False).encode('utf-8'))

    def log_message(self, format, *args):
        """Custom log format."""
        if '/api/' in args[0]:
            print(f"  API: {args[0]}")
        elif args[0].startswith('GET / ') or 'index.html' in args[0]:
            pass  # Don't log index.html requests
        else:
            print(f"  {args[0]}")


# =============================================================================
# MAIN
# =============================================================================

def main():
    parser = argparse.ArgumentParser(description='Serve Hybrid Cloud Infrastructure Documentation')
    parser.add_argument('--port', '-p', type=int, default=8080, help='Port to serve on (default: 8080)')
    parser.add_argument('--host', '-H', type=str, default='localhost', help='Host to bind to (default: localhost)')
    args = parser.parse_args()

    # Print banner
    print()
    print("=" * 65)
    print("  HYBRID CLOUD INFRASTRUCTURE - DOCUMENTATION SERVER")
    print("=" * 65)
    print()
    print(f"  Repository: {REPO_ROOT}")
    print(f"  Server:     http://{args.host}:{args.port}")
    print()
    print("  API Endpoints:")
    print("    GET /api/tree          - Full repository tree")
    print("    GET /api/file?path=... - Read file content")
    print("    GET /api/search?q=...  - Search files")
    print()
    print("=" * 65)
    print()
    print("  Press Ctrl+C to stop the server")
    print()

    # Start server
    server = HTTPServer((args.host, args.port), DocsHandler)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n\n  Server stopped.")
        server.shutdown()


if __name__ == "__main__":
    main()
