#!/usr/bin/env python3
"""
=============================================================================
HYBRID CLOUD INFRASTRUCTURE - REPOSITORY EXPLORER GENERATOR
=============================================================================

This script generates a beautiful, interactive visual file explorer for
the entire repository. It scans all files/folders and creates a clickable,
color-coded tree view that gets injected into the documentation site.

Features:
- Color-coded by file type (Terraform, Ansible, Shell, YAML, etc.)
- Expandable folder structure
- File descriptions and purposes
- Respects .gitignore patterns (no secrets exposed)
- Shows file sizes and modification dates
- Searchable file tree
- Statistics dashboard

Usage:
    python3 generate-repo-explorer.py

Output:
    Updates deployment-site/index.html with current repo structure

Author: Auto-generated for Hybrid Cloud Infrastructure
=============================================================================
"""

import os
import re
import json
import fnmatch
from datetime import datetime
from pathlib import Path
from collections import defaultdict

# =============================================================================
# CONFIGURATION
# =============================================================================

REPO_ROOT = Path(__file__).parent.parent
OUTPUT_FILE = REPO_ROOT / "deployment-site" / "index.html"

# Security: Patterns to ALWAYS exclude (matches .gitignore + extra safety)
EXCLUDE_PATTERNS = [
    # Terraform secrets
    "*.tfvars",
    "*.tfvars.json",
    "*.tfstate",
    "*.tfstate.*",
    ".terraform/",
    ".terraform.lock.hcl",

    # Keys and credentials
    "key*",
    "Key*",
    "*.pem",
    "*.key",
    "*.crt",
    "id_rsa*",
    "id_ed25519*",
    "*.pub",

    # Ansible vault
    ".ansible_vault",
    "*vault_password*",

    # Network backups with credentials
    "network/**/backups/*.cfg",
    "network/router/mikrotik/backups/**",
    "*.bin",
    "*.rsc",

    # Environment files
    ".env",
    ".env.*",
    "*.env",

    # Git internals
    ".git/",
    ".gitignore",

    # IDE and system files
    ".idea/",
    ".vscode/",
    "*.swp",
    "*.swo",
    ".DS_Store",
    "Thumbs.db",

    # Python
    "__pycache__/",
    "*.pyc",
    "*.pyo",
    ".pytest_cache/",
    "venv/",
    ".venv/",

    # Node
    "node_modules/",

    # Build outputs
    "dist/",
    "build/",
    "*.log",
]

# File type definitions with colors and icons
FILE_TYPES = {
    # Terraform
    ".tf": {"color": "#844FBA", "icon": "⬡", "category": "terraform", "label": "Terraform"},

    # Ansible/YAML
    ".yml": {"color": "#E34F26", "icon": "📋", "category": "ansible", "label": "YAML"},
    ".yaml": {"color": "#E34F26", "icon": "📋", "category": "ansible", "label": "YAML"},
    ".j2": {"color": "#B41717", "icon": "🔧", "category": "ansible", "label": "Jinja2 Template"},

    # Shell scripts
    ".sh": {"color": "#4EAA25", "icon": "⚡", "category": "shell", "label": "Shell Script"},
    ".bash": {"color": "#4EAA25", "icon": "⚡", "category": "shell", "label": "Bash Script"},

    # Documentation
    ".md": {"color": "#083FA1", "icon": "📖", "category": "docs", "label": "Markdown"},
    ".txt": {"color": "#6E7681", "icon": "📝", "category": "docs", "label": "Text"},
    ".rst": {"color": "#083FA1", "icon": "📖", "category": "docs", "label": "reStructuredText"},

    # Web
    ".html": {"color": "#E44D26", "icon": "🌐", "category": "web", "label": "HTML"},
    ".css": {"color": "#264DE4", "icon": "🎨", "category": "web", "label": "CSS"},
    ".js": {"color": "#F7DF1E", "icon": "📜", "category": "web", "label": "JavaScript"},

    # Config
    ".json": {"color": "#000000", "icon": "📦", "category": "config", "label": "JSON"},
    ".toml": {"color": "#9C4121", "icon": "⚙️", "category": "config", "label": "TOML"},
    ".ini": {"color": "#6E7681", "icon": "⚙️", "category": "config", "label": "INI"},
    ".conf": {"color": "#6E7681", "icon": "⚙️", "category": "config", "label": "Config"},
    ".cfg": {"color": "#6E7681", "icon": "⚙️", "category": "config", "label": "Config"},

    # Docker/Containers
    "Dockerfile": {"color": "#2496ED", "icon": "🐳", "category": "docker", "label": "Dockerfile"},
    ".dockerignore": {"color": "#2496ED", "icon": "🐳", "category": "docker", "label": "Docker Ignore"},

    # Kubernetes
    ".kubeconfig": {"color": "#326CE5", "icon": "☸️", "category": "k8s", "label": "Kubeconfig"},

    # Python
    ".py": {"color": "#3776AB", "icon": "🐍", "category": "python", "label": "Python"},

    # Go
    ".go": {"color": "#00ADD8", "icon": "🔷", "category": "go", "label": "Go"},

    # Default
    "default": {"color": "#6E7681", "icon": "📄", "category": "other", "label": "File"},
}

# Folder type definitions
FOLDER_TYPES = {
    "terraform": {"color": "#844FBA", "icon": "⬡"},
    "ansible": {"color": "#E34F26", "icon": "🔧"},
    "playbooks": {"color": "#E34F26", "icon": "▶️"},
    ".github": {"color": "#6E5494", "icon": "🔄"},
    "workflows": {"color": "#2088FF", "icon": "⚡"},
    "network": {"color": "#00B4D8", "icon": "🌐"},
    "proxmox": {"color": "#E57000", "icon": "🖥️"},
    "aws": {"color": "#FF9900", "icon": "☁️"},
    "hashicorp": {"color": "#000000", "icon": "🔐"},
    "vault": {"color": "#000000", "icon": "🔐"},
    "k8s": {"color": "#326CE5", "icon": "☸️"},
    "kubernetes": {"color": "#326CE5", "icon": "☸️"},
    "freeipa": {"color": "#4E9A06", "icon": "🔑"},
    "nginx": {"color": "#009639", "icon": "🔀"},
    "scripts": {"color": "#4EAA25", "icon": "📜"},
    "docs": {"color": "#083FA1", "icon": "📚"},
    "deployment-docs": {"color": "#083FA1", "icon": "📚"},
    "deployment-site": {"color": "#E44D26", "icon": "🌍"},
    "troubleshooting": {"color": "#F85149", "icon": "🔧"},
    "inventory": {"color": "#E34F26", "icon": "📋"},
    "group_vars": {"color": "#E34F26", "icon": "📦"},
    "templates": {"color": "#B41717", "icon": "📑"},
    "roles": {"color": "#E34F26", "icon": "🎭"},
    "common": {"color": "#6E7681", "icon": "📁"},
    "lxc": {"color": "#E57000", "icon": "📦"},
    "vms": {"color": "#E57000", "icon": "💻"},
    "storage": {"color": "#FF6B35", "icon": "💾"},
    "compute": {"color": "#FF9900", "icon": "🖥️"},
    "iam": {"color": "#FF9900", "icon": "👤"},
    "secrets": {"color": "#FF9900", "icon": "🔒"},
    "vpn": {"color": "#00B4D8", "icon": "🔗"},
    "router": {"color": "#00B4D8", "icon": "📡"},
    "switch": {"color": "#00B4D8", "icon": "🔌"},
    "ap": {"color": "#00B4D8", "icon": "📶"},
    "backups": {"color": "#6E7681", "icon": "💾"},
    "golden_templates": {"color": "#FFD700", "icon": "⭐"},
    "golden-template": {"color": "#FFD700", "icon": "⭐"},
    "golden-image": {"color": "#FFD700", "icon": "⭐"},
    "bootstrap_proxmox": {"color": "#E57000", "icon": "🚀"},
    "dev": {"color": "#58A6FF", "icon": "🔵"},
    "prod": {"color": "#3FB950", "icon": "🟢"},
    "default": {"color": "#8B949E", "icon": "📁"},
}

# Folder descriptions for documentation
FOLDER_DESCRIPTIONS = {
    "terraform": "Infrastructure as Code - Terraform configurations for provisioning resources",
    "ansible": "Configuration Management - Ansible playbooks, roles, and inventory",
    "playbooks": "Ansible playbooks for automated configuration and deployment",
    ".github": "GitHub configuration including Actions workflows and templates",
    "workflows": "GitHub Actions CI/CD workflow definitions",
    "network": "Network infrastructure configurations (router, switch, VPN)",
    "proxmox": "Proxmox VE hypervisor setup scripts and configurations",
    "aws": "AWS cloud resource configurations and CloudFormation templates",
    "hashicorp": "HashiCorp tools (Vault, Consul, etc.) configurations",
    "vault": "HashiCorp Vault secrets management cluster",
    "k8s": "Kubernetes cluster configurations and manifests",
    "kubernetes": "Kubernetes cluster configurations and manifests",
    "freeipa": "FreeIPA identity management (Kerberos, LDAP, DNS)",
    "nginx": "Nginx reverse proxy and load balancer configurations",
    "scripts": "Utility scripts for various operations",
    "deployment-docs": "Step-by-step deployment documentation guides",
    "deployment-site": "Interactive HTML documentation site",
    "troubleshooting": "Troubleshooting guides and case studies",
    "inventory": "Ansible inventory files defining target hosts",
    "group_vars": "Ansible group variables for host configuration",
    "templates": "Jinja2 templates for configuration file generation",
    "roles": "Reusable Ansible roles",
    "lxc": "Linux Container (LXC) Terraform modules",
    "vms": "Virtual Machine Terraform modules",
    "storage": "Storage configuration (NAS, NFS, volumes)",
    "compute": "Compute resource configurations (EC2, instances)",
    "iam": "AWS IAM roles, policies, and users",
    "secrets": "AWS Secrets Manager configurations",
    "vpn": "WireGuard VPN tunnel configurations",
    "router": "Router configurations (MikroTik)",
    "switch": "Network switch configurations",
    "ap": "WiFi Access Point configurations",
    "golden_templates": "Base VM/LXC templates for cloning",
    "bootstrap_proxmox": "Proxmox initial setup and bootstrap scripts",
    "dev": "Development environment configurations",
    "prod": "Production environment configurations",
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

def should_exclude(path: Path, relative_path: str) -> bool:
    """Check if a path should be excluded based on security patterns."""
    name = path.name

    for pattern in EXCLUDE_PATTERNS:
        # Handle directory patterns
        if pattern.endswith('/'):
            dir_pattern = pattern[:-1]
            if name == dir_pattern or fnmatch.fnmatch(name, dir_pattern):
                return True
            if f"/{dir_pattern}/" in f"/{relative_path}/":
                return True
        # Handle glob patterns with **
        elif '**' in pattern:
            # Convert ** glob to regex-friendly pattern
            regex_pattern = pattern.replace('**', '.*').replace('*', '[^/]*')
            if re.match(regex_pattern, relative_path):
                return True
        # Handle simple glob patterns
        elif fnmatch.fnmatch(name, pattern):
            return True
        elif fnmatch.fnmatch(relative_path, pattern):
            return True

    return False


def get_file_type(path: Path) -> dict:
    """Get file type information based on extension or name."""
    name = path.name
    ext = path.suffix.lower()

    # Check for special filenames first
    if name in FILE_TYPES:
        return FILE_TYPES[name]

    # Check extension
    if ext in FILE_TYPES:
        return FILE_TYPES[ext]

    return FILE_TYPES["default"]


def get_folder_type(name: str) -> dict:
    """Get folder type information based on name."""
    name_lower = name.lower()

    if name_lower in FOLDER_TYPES:
        return FOLDER_TYPES[name_lower]

    # Check partial matches
    for key in FOLDER_TYPES:
        if key in name_lower:
            return FOLDER_TYPES[key]

    return FOLDER_TYPES["default"]


def get_folder_description(name: str) -> str:
    """Get folder description if available."""
    name_lower = name.lower()

    if name_lower in FOLDER_DESCRIPTIONS:
        return FOLDER_DESCRIPTIONS[name_lower]

    for key, desc in FOLDER_DESCRIPTIONS.items():
        if key in name_lower:
            return desc

    return ""


def format_size(size: int) -> str:
    """Format file size in human-readable format."""
    for unit in ['B', 'KB', 'MB', 'GB']:
        if size < 1024:
            return f"{size:.1f} {unit}" if unit != 'B' else f"{size} {unit}"
        size /= 1024
    return f"{size:.1f} TB"


def get_file_stats(path: Path) -> dict:
    """Get file statistics."""
    try:
        stat = path.stat()
        return {
            "size": stat.st_size,
            "size_formatted": format_size(stat.st_size),
            "modified": datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d %H:%M"),
        }
    except:
        return {"size": 0, "size_formatted": "N/A", "modified": "N/A"}


# =============================================================================
# TREE SCANNING
# =============================================================================

def scan_directory(path: Path, relative_base: Path = None) -> dict:
    """Recursively scan a directory and build tree structure."""
    if relative_base is None:
        relative_base = path

    relative_path = str(path.relative_to(relative_base))
    if relative_path == '.':
        relative_path = ''

    # Check exclusion
    if should_exclude(path, relative_path):
        return None

    if path.is_file():
        file_type = get_file_type(path)
        stats = get_file_stats(path)
        return {
            "type": "file",
            "name": path.name,
            "path": relative_path,
            "extension": path.suffix.lower(),
            "file_type": file_type,
            "stats": stats,
        }

    elif path.is_dir():
        folder_type = get_folder_type(path.name)
        description = get_folder_description(path.name)

        children = []
        try:
            for child in sorted(path.iterdir(), key=lambda x: (x.is_file(), x.name.lower())):
                child_data = scan_directory(child, relative_base)
                if child_data:
                    children.append(child_data)
        except PermissionError:
            pass

        # Skip empty directories
        if not children and relative_path:
            return None

        return {
            "type": "directory",
            "name": path.name if relative_path else "hybrid-cloud-infrastructure",
            "path": relative_path,
            "folder_type": folder_type,
            "description": description,
            "children": children,
            "file_count": sum(1 for c in children if c["type"] == "file"),
            "dir_count": sum(1 for c in children if c["type"] == "directory"),
        }

    return None


def collect_statistics(tree: dict) -> dict:
    """Collect statistics from the tree."""
    stats = {
        "total_files": 0,
        "total_dirs": 0,
        "total_size": 0,
        "by_category": defaultdict(int),
        "by_extension": defaultdict(int),
    }

    def traverse(node):
        if node["type"] == "file":
            stats["total_files"] += 1
            stats["total_size"] += node["stats"]["size"]
            stats["by_category"][node["file_type"]["category"]] += 1
            stats["by_extension"][node["extension"]] += 1
        else:
            stats["total_dirs"] += 1
            for child in node.get("children", []):
                traverse(child)

    traverse(tree)
    stats["total_size_formatted"] = format_size(stats["total_size"])
    stats["by_category"] = dict(stats["by_category"])
    stats["by_extension"] = dict(stats["by_extension"])

    return stats


# =============================================================================
# HTML GENERATION
# =============================================================================

def generate_tree_html(node: dict, depth: int = 0) -> str:
    """Generate HTML for a tree node."""
    indent = "    " * depth

    if node["type"] == "file":
        file_type = node["file_type"]
        stats = node["stats"]

        return f'''{indent}<div class="repo-file" data-path="{node['path']}" data-ext="{node['extension']}" data-category="{file_type['category']}">
{indent}    <div class="repo-file-header" onclick="toggleRepoItem(this)">
{indent}        <span class="repo-icon" style="color: {file_type['color']}">{file_type['icon']}</span>
{indent}        <span class="repo-name">{node['name']}</span>
{indent}        <span class="repo-meta">
{indent}            <span class="repo-type-badge" style="background: {file_type['color']}20; color: {file_type['color']}">{file_type['label']}</span>
{indent}            <span class="repo-size">{stats['size_formatted']}</span>
{indent}        </span>
{indent}        <span class="repo-expand-icon">▶</span>
{indent}    </div>
{indent}    <div class="repo-file-detail">
{indent}        <div class="repo-detail-row"><span class="repo-detail-label">Path:</span><code class="repo-detail-value">{node['path']}</code></div>
{indent}        <div class="repo-detail-row"><span class="repo-detail-label">Type:</span><span class="repo-detail-value">{file_type['label']}</span></div>
{indent}        <div class="repo-detail-row"><span class="repo-detail-label">Size:</span><span class="repo-detail-value">{stats['size_formatted']}</span></div>
{indent}        <div class="repo-detail-row"><span class="repo-detail-label">Modified:</span><span class="repo-detail-value">{stats['modified']}</span></div>
{indent}    </div>
{indent}</div>
'''

    else:  # directory
        folder_type = node["folder_type"]
        children_html = "\n".join(generate_tree_html(child, depth + 1) for child in node.get("children", []))

        description_html = ""
        if node["description"]:
            description_html = f'''
{indent}        <div class="repo-folder-desc">{node['description']}</div>'''

        counts = f'{node["dir_count"]} folders, {node["file_count"]} files' if depth > 0 else ""

        return f'''{indent}<div class="repo-folder {'repo-root' if depth == 0 else ''}" data-path="{node['path']}">
{indent}    <div class="repo-folder-header" onclick="toggleRepoFolder(this)">
{indent}        <span class="repo-folder-icon" style="color: {folder_type['color']}">{folder_type['icon']}</span>
{indent}        <span class="repo-folder-name">{node['name']}/</span>
{indent}        <span class="repo-folder-meta">{counts}</span>
{indent}        <span class="repo-folder-toggle">▼</span>
{indent}    </div>{description_html}
{indent}    <div class="repo-folder-children">
{children_html}
{indent}    </div>
{indent}</div>
'''


def generate_stats_html(stats: dict) -> str:
    """Generate statistics dashboard HTML."""
    # Category cards
    category_cards = ""
    category_colors = {
        "terraform": "#844FBA",
        "ansible": "#E34F26",
        "shell": "#4EAA25",
        "docs": "#083FA1",
        "web": "#E44D26",
        "config": "#6E7681",
        "docker": "#2496ED",
        "k8s": "#326CE5",
        "python": "#3776AB",
        "other": "#6E7681",
    }

    for category, count in sorted(stats["by_category"].items(), key=lambda x: -x[1]):
        color = category_colors.get(category, "#6E7681")
        category_cards += f'''
                                <div class="repo-stat-card" style="border-left-color: {color}">
                                    <div class="repo-stat-value" style="color: {color}">{count}</div>
                                    <div class="repo-stat-label">{category.title()} Files</div>
                                </div>'''

    return f'''
                            <div class="repo-stats-grid">
                                <div class="repo-stat-card repo-stat-primary">
                                    <div class="repo-stat-value">{stats['total_files']}</div>
                                    <div class="repo-stat-label">Total Files</div>
                                </div>
                                <div class="repo-stat-card repo-stat-primary">
                                    <div class="repo-stat-value">{stats['total_dirs']}</div>
                                    <div class="repo-stat-label">Directories</div>
                                </div>
                                <div class="repo-stat-card repo-stat-primary">
                                    <div class="repo-stat-value">{stats['total_size_formatted']}</div>
                                    <div class="repo-stat-label">Total Size</div>
                                </div>
                            </div>

                            <h4 style="margin: 24px 0 16px; color: var(--text-secondary);">Files by Category</h4>
                            <div class="repo-stats-grid repo-stats-categories">
                                {category_cards}
                            </div>'''


def generate_explorer_page(tree: dict, stats: dict) -> str:
    """Generate the complete Repository Explorer page HTML."""
    tree_html = generate_tree_html(tree)
    stats_html = generate_stats_html(stats)

    return f'''
            <!-- ==========================================
                 PAGE: REPOSITORY EXPLORER
                 ========================================== -->
            <div class="page" id="page-repo-explorer">
                <div class="content-header">
                    <div class="breadcrumb">
                        <span>Reference</span>
                        <span class="breadcrumb-sep">/</span>
                        <span class="breadcrumb-current">Repository Explorer</span>
                    </div>
                    <h1 class="page-title">Repository Explorer <span class="title-badge reference">🗂️</span></h1>
                </div>
                <div class="content-body">
                    <div class="info-box tip">
                        <div class="info-box-title">📁 Live Repository Structure</div>
                        <div class="info-box-content">
                            This is a visual map of the entire repository. Click any folder to expand/collapse, click any file to see details.
                            <br><br>
                            <strong>Last generated:</strong> {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
                            <br>
                            <strong>To refresh:</strong> Run <code>python3 deployment-site/generate-repo-explorer.py</code>
                        </div>
                    </div>

                    <div class="tabs-container">
                        <div class="tabs-header">
                            <button class="tab-btn active" onclick="switchTab(event, 'repo-tree')">File Tree</button>
                            <button class="tab-btn" onclick="switchTab(event, 'repo-stats')">Statistics</button>
                            <button class="tab-btn" onclick="switchTab(event, 'repo-search')">Search</button>
                        </div>

                        <div class="tab-content active" id="repo-tree">
                            <div class="repo-controls">
                                <button class="repo-btn" onclick="expandAllFolders()">Expand All</button>
                                <button class="repo-btn" onclick="collapseAllFolders()">Collapse All</button>
                                <div class="repo-filter">
                                    <span class="repo-filter-label">Filter:</span>
                                    <button class="repo-filter-btn active" onclick="filterByCategory(this, 'all')">All</button>
                                    <button class="repo-filter-btn" onclick="filterByCategory(this, 'terraform')" style="color: #844FBA">Terraform</button>
                                    <button class="repo-filter-btn" onclick="filterByCategory(this, 'ansible')" style="color: #E34F26">Ansible</button>
                                    <button class="repo-filter-btn" onclick="filterByCategory(this, 'shell')" style="color: #4EAA25">Shell</button>
                                    <button class="repo-filter-btn" onclick="filterByCategory(this, 'docs')" style="color: #083FA1">Docs</button>
                                </div>
                            </div>

                            <div class="repo-tree-container">
{tree_html}
                            </div>
                        </div>

                        <div class="tab-content" id="repo-stats">
                            <h3>Repository Statistics</h3>
                            {stats_html}
                        </div>

                        <div class="tab-content" id="repo-search">
                            <h3>Search Files</h3>
                            <div class="repo-search-box">
                                <input type="text" id="repoSearchInput" placeholder="Search files and folders..." onkeyup="searchRepo()">
                            </div>
                            <div id="repoSearchResults" class="repo-search-results">
                                <p class="repo-search-hint">Type to search across all files and folders...</p>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
'''


def generate_css() -> str:
    """Generate CSS for the Repository Explorer."""
    return '''
        /* ========================================
           REPOSITORY EXPLORER STYLES
           ======================================== */

        /* Controls */
        .repo-controls {
            display: flex;
            align-items: center;
            gap: 16px;
            margin-bottom: 20px;
            padding: 12px 16px;
            background: var(--bg-card);
            border: 1px solid var(--border);
            border-radius: 8px;
            flex-wrap: wrap;
        }

        .repo-btn {
            padding: 6px 14px;
            background: var(--bg-hover);
            border: 1px solid var(--border);
            border-radius: 6px;
            color: var(--text-secondary);
            font-size: 12px;
            cursor: pointer;
            transition: all 0.15s;
        }

        .repo-btn:hover {
            background: var(--border);
            color: var(--text-primary);
        }

        .repo-filter {
            display: flex;
            align-items: center;
            gap: 8px;
            margin-left: auto;
        }

        .repo-filter-label {
            font-size: 12px;
            color: var(--text-muted);
        }

        .repo-filter-btn {
            padding: 4px 10px;
            background: transparent;
            border: 1px solid var(--border);
            border-radius: 4px;
            color: var(--text-muted);
            font-size: 11px;
            cursor: pointer;
            transition: all 0.15s;
        }

        .repo-filter-btn:hover {
            border-color: var(--text-muted);
        }

        .repo-filter-btn.active {
            background: var(--accent-blue);
            border-color: var(--accent-blue);
            color: white;
        }

        /* Tree Container */
        .repo-tree-container {
            background: var(--code-bg);
            border: 1px solid var(--border);
            border-radius: 8px;
            padding: 16px;
            max-height: 70vh;
            overflow: auto;
        }

        /* Folder Styles */
        .repo-folder {
            margin: 2px 0;
        }

        .repo-root {
            margin: 0;
        }

        .repo-folder-header {
            display: flex;
            align-items: center;
            gap: 8px;
            padding: 8px 12px;
            border-radius: 6px;
            cursor: pointer;
            transition: background 0.15s;
        }

        .repo-folder-header:hover {
            background: var(--bg-hover);
        }

        .repo-folder.collapsed .repo-folder-header {
            background: transparent;
        }

        .repo-folder-icon {
            font-size: 16px;
            width: 24px;
            text-align: center;
        }

        .repo-folder-name {
            font-family: 'SFMono-Regular', Consolas, monospace;
            font-size: 14px;
            font-weight: 600;
            color: var(--accent-blue);
        }

        .repo-folder-meta {
            font-size: 11px;
            color: var(--text-muted);
            margin-left: auto;
        }

        .repo-folder-toggle {
            font-size: 10px;
            color: var(--text-muted);
            transition: transform 0.2s;
        }

        .repo-folder.collapsed .repo-folder-toggle {
            transform: rotate(-90deg);
        }

        .repo-folder-desc {
            font-size: 12px;
            color: var(--text-muted);
            padding: 4px 12px 8px 44px;
            font-style: italic;
        }

        .repo-folder-children {
            margin-left: 24px;
            border-left: 1px solid var(--border);
            padding-left: 8px;
        }

        .repo-folder.collapsed .repo-folder-children {
            display: none;
        }

        .repo-folder.collapsed .repo-folder-desc {
            display: none;
        }

        /* File Styles */
        .repo-file {
            margin: 2px 0;
        }

        .repo-file-header {
            display: flex;
            align-items: center;
            gap: 8px;
            padding: 6px 12px;
            border-radius: 6px;
            cursor: pointer;
            transition: background 0.15s;
        }

        .repo-file-header:hover {
            background: var(--bg-hover);
        }

        .repo-file.expanded .repo-file-header {
            background: var(--bg-active);
        }

        .repo-icon {
            font-size: 14px;
            width: 24px;
            text-align: center;
        }

        .repo-name {
            font-family: 'SFMono-Regular', Consolas, monospace;
            font-size: 13px;
            color: var(--text-secondary);
        }

        .repo-meta {
            display: flex;
            align-items: center;
            gap: 8px;
            margin-left: auto;
        }

        .repo-type-badge {
            font-size: 10px;
            padding: 2px 8px;
            border-radius: 10px;
            font-weight: 500;
        }

        .repo-size {
            font-size: 11px;
            color: var(--text-muted);
            min-width: 60px;
            text-align: right;
        }

        .repo-expand-icon {
            font-size: 10px;
            color: var(--text-muted);
            transition: transform 0.2s;
        }

        .repo-file.expanded .repo-expand-icon {
            transform: rotate(90deg);
            color: var(--accent-blue);
        }

        .repo-file-detail {
            display: none;
            margin: 4px 0 8px 32px;
            padding: 12px;
            background: var(--bg-panel);
            border: 1px solid var(--border);
            border-radius: 6px;
        }

        .repo-file.expanded .repo-file-detail {
            display: block;
        }

        .repo-detail-row {
            display: flex;
            padding: 4px 0;
            font-size: 12px;
        }

        .repo-detail-label {
            width: 80px;
            color: var(--text-muted);
        }

        .repo-detail-value {
            color: var(--text-secondary);
        }

        .repo-detail-value code {
            background: var(--bg-card);
            padding: 2px 6px;
            border-radius: 3px;
            font-size: 11px;
            color: var(--accent-cyan);
        }

        /* Statistics */
        .repo-stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
            gap: 16px;
        }

        .repo-stat-card {
            background: var(--bg-card);
            border: 1px solid var(--border);
            border-left: 4px solid var(--accent-blue);
            border-radius: 8px;
            padding: 16px;
            text-align: center;
        }

        .repo-stat-card.repo-stat-primary {
            border-left-color: var(--accent-blue);
        }

        .repo-stat-value {
            font-size: 24px;
            font-weight: 700;
            color: var(--accent-blue);
            margin-bottom: 4px;
        }

        .repo-stat-label {
            font-size: 11px;
            color: var(--text-muted);
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .repo-stats-categories {
            grid-template-columns: repeat(auto-fill, minmax(120px, 1fr));
        }

        .repo-stats-categories .repo-stat-card {
            padding: 12px;
        }

        .repo-stats-categories .repo-stat-value {
            font-size: 20px;
        }

        /* Search */
        .repo-search-box {
            margin-bottom: 20px;
        }

        .repo-search-box input {
            width: 100%;
            padding: 12px 16px;
            background: var(--bg-card);
            border: 1px solid var(--border);
            border-radius: 8px;
            color: var(--text-primary);
            font-size: 14px;
        }

        .repo-search-box input:focus {
            outline: none;
            border-color: var(--accent-blue);
        }

        .repo-search-results {
            max-height: 60vh;
            overflow-y: auto;
        }

        .repo-search-hint {
            color: var(--text-muted);
            text-align: center;
            padding: 40px;
        }

        .repo-search-result {
            display: flex;
            align-items: center;
            gap: 12px;
            padding: 10px 16px;
            border-bottom: 1px solid var(--border);
            cursor: pointer;
            transition: background 0.15s;
        }

        .repo-search-result:hover {
            background: var(--bg-hover);
        }

        .repo-search-result .repo-icon {
            font-size: 16px;
        }

        .repo-search-result-info {
            flex: 1;
        }

        .repo-search-result-name {
            font-weight: 500;
            color: var(--text-primary);
        }

        .repo-search-result-path {
            font-size: 12px;
            color: var(--text-muted);
            font-family: 'SFMono-Regular', Consolas, monospace;
        }

        /* Hidden filter state */
        .repo-file.filtered-out,
        .repo-folder.filtered-out {
            display: none;
        }
'''


def generate_javascript() -> str:
    """Generate JavaScript for the Repository Explorer."""
    return '''
        // ========================================
        // REPOSITORY EXPLORER FUNCTIONS
        // ========================================

        function toggleRepoFolder(header) {
            const folder = header.closest('.repo-folder');
            folder.classList.toggle('collapsed');
        }

        function toggleRepoItem(header) {
            const item = header.closest('.repo-file');
            item.classList.toggle('expanded');
        }

        function expandAllFolders() {
            document.querySelectorAll('.repo-folder.collapsed').forEach(f => {
                f.classList.remove('collapsed');
            });
        }

        function collapseAllFolders() {
            document.querySelectorAll('.repo-folder:not(.repo-root)').forEach(f => {
                f.classList.add('collapsed');
            });
        }

        function filterByCategory(btn, category) {
            // Update active button
            document.querySelectorAll('.repo-filter-btn').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');

            // Filter files
            document.querySelectorAll('.repo-file').forEach(file => {
                if (category === 'all' || file.dataset.category === category) {
                    file.classList.remove('filtered-out');
                } else {
                    file.classList.add('filtered-out');
                }
            });

            // Show/hide empty folders
            updateFolderVisibility();
        }

        function updateFolderVisibility() {
            // Check each folder from deepest to root
            const folders = Array.from(document.querySelectorAll('.repo-folder')).reverse();
            folders.forEach(folder => {
                const visibleChildren = folder.querySelectorAll(':scope > .repo-folder-children > .repo-file:not(.filtered-out), :scope > .repo-folder-children > .repo-folder:not(.filtered-out)');
                if (visibleChildren.length === 0 && !folder.classList.contains('repo-root')) {
                    folder.classList.add('filtered-out');
                } else {
                    folder.classList.remove('filtered-out');
                }
            });
        }

        function searchRepo() {
            const query = document.getElementById('repoSearchInput').value.toLowerCase();
            const resultsContainer = document.getElementById('repoSearchResults');

            if (query.length < 2) {
                resultsContainer.innerHTML = '<p class="repo-search-hint">Type at least 2 characters to search...</p>';
                return;
            }

            const files = document.querySelectorAll('.repo-file');
            const matches = [];

            files.forEach(file => {
                const name = file.querySelector('.repo-name').textContent.toLowerCase();
                const path = file.dataset.path.toLowerCase();

                if (name.includes(query) || path.includes(query)) {
                    const icon = file.querySelector('.repo-icon').textContent;
                    const iconColor = file.querySelector('.repo-icon').style.color;
                    const badge = file.querySelector('.repo-type-badge').textContent;
                    matches.push({
                        name: file.querySelector('.repo-name').textContent,
                        path: file.dataset.path,
                        icon: icon,
                        iconColor: iconColor,
                        badge: badge,
                    });
                }
            });

            if (matches.length === 0) {
                resultsContainer.innerHTML = '<p class="repo-search-hint">No files found matching "' + query + '"</p>';
                return;
            }

            let html = matches.slice(0, 50).map(m => `
                <div class="repo-search-result" onclick="jumpToFile('${m.path}')">
                    <span class="repo-icon" style="color: ${m.iconColor}">${m.icon}</span>
                    <div class="repo-search-result-info">
                        <div class="repo-search-result-name">${m.name}</div>
                        <div class="repo-search-result-path">${m.path}</div>
                    </div>
                    <span class="repo-type-badge">${m.badge}</span>
                </div>
            `).join('');

            if (matches.length > 50) {
                html += '<p style="text-align: center; color: var(--text-muted); padding: 16px;">Showing first 50 of ' + matches.length + ' results</p>';
            }

            resultsContainer.innerHTML = html;
        }

        function jumpToFile(path) {
            // Switch to tree tab
            const treeTab = document.querySelector('[onclick*="repo-tree"]');
            if (treeTab) treeTab.click();

            // Find and expand path
            const file = document.querySelector('.repo-file[data-path="' + path + '"]');
            if (file) {
                // Expand all parent folders
                let parent = file.parentElement;
                while (parent) {
                    if (parent.classList.contains('repo-folder')) {
                        parent.classList.remove('collapsed');
                    }
                    parent = parent.parentElement;
                }

                // Scroll to and highlight file
                file.scrollIntoView({ behavior: 'smooth', block: 'center' });
                file.classList.add('expanded');
                file.style.animation = 'highlight-pulse 1s ease';
                setTimeout(() => file.style.animation = '', 1000);
            }
        }

        // Highlight animation
        const style = document.createElement('style');
        style.textContent = `
            @keyframes highlight-pulse {
                0%, 100% { background: transparent; }
                50% { background: var(--accent-blue)30; }
            }
        `;
        document.head.appendChild(style);
'''


# =============================================================================
# NAV ITEM GENERATION
# =============================================================================

def generate_nav_item() -> str:
    """Generate the navigation item for Repository Explorer."""
    return '''                <div class="nav-item" onclick="showPage('repo-explorer')" data-search="repository explorer files folders structure tree">
                    <span class="step-badge reference">🗂️</span>
                    <div class="nav-item-content">
                        <div class="nav-item-title">Repository Explorer</div>
                        <div class="nav-item-desc">Visual File Browser</div>
                    </div>
                </div>'''


# =============================================================================
# MAIN INJECTION LOGIC
# =============================================================================

def inject_into_html(html_content: str, explorer_page: str, css: str, js: str, nav_item: str) -> str:
    """Inject the generated content into the existing HTML file."""

    # 1. Inject CSS before the closing </style> tag
    css_marker = "    </style>"
    if css_marker in html_content:
        # Check if our CSS is already there
        if "REPOSITORY EXPLORER STYLES" not in html_content:
            html_content = html_content.replace(css_marker, css + "\n" + css_marker)

    # 2. Inject the nav item before the Quick Commands nav item
    nav_marker = '''                <div class="nav-item" onclick="showPage('commands')'''
    if nav_marker in html_content:
        # Check if our nav item is already there
        if "showPage('repo-explorer')" not in html_content:
            html_content = html_content.replace(nav_marker, nav_item + "\n" + nav_marker)

    # 3. Inject/Replace the explorer page
    # Look for existing explorer page
    explorer_start_marker = "<!-- ==========================================\n                 PAGE: REPOSITORY EXPLORER"
    explorer_end_marker = '            </div>\n\n            <!-- ==========================================\n                 PAGE: QUICK COMMANDS'

    if explorer_start_marker in html_content:
        # Replace existing
        pattern = r'<!-- =+\s*PAGE: REPOSITORY EXPLORER.*?(?=<!-- =+\s*PAGE: QUICK COMMANDS)'
        html_content = re.sub(pattern, explorer_page.strip() + '\n\n            ', html_content, flags=re.DOTALL)
    else:
        # Insert before Quick Commands page
        quick_commands_marker = '''            <!-- ==========================================
                 PAGE: QUICK COMMANDS'''
        if quick_commands_marker in html_content:
            html_content = html_content.replace(quick_commands_marker, explorer_page + "\n" + quick_commands_marker)

    # 4. Inject JavaScript before the closing </script> tag
    js_marker = "    </script>"
    if js_marker in html_content:
        # Check if our JS is already there
        if "REPOSITORY EXPLORER FUNCTIONS" not in html_content:
            html_content = html_content.replace(js_marker, js + "\n" + js_marker)

    return html_content


# =============================================================================
# MAIN EXECUTION
# =============================================================================

def main():
    print("=" * 60)
    print("REPOSITORY EXPLORER GENERATOR")
    print("=" * 60)
    print()

    # Scan the repository
    print(f"📂 Scanning repository: {REPO_ROOT}")
    tree = scan_directory(REPO_ROOT)

    if not tree:
        print("❌ Error: Could not scan repository")
        return 1

    # Collect statistics
    print("📊 Collecting statistics...")
    stats = collect_statistics(tree)
    print(f"   Found {stats['total_files']} files in {stats['total_dirs']} directories")
    print(f"   Total size: {stats['total_size_formatted']}")

    # Generate HTML components
    print("🎨 Generating HTML...")
    explorer_page = generate_explorer_page(tree, stats)
    css = generate_css()
    js = generate_javascript()
    nav_item = generate_nav_item()

    # Read existing HTML
    print(f"📖 Reading {OUTPUT_FILE}...")
    if not OUTPUT_FILE.exists():
        print(f"❌ Error: {OUTPUT_FILE} not found")
        return 1

    with open(OUTPUT_FILE, 'r', encoding='utf-8') as f:
        html_content = f.read()

    # Inject content
    print("💉 Injecting content...")
    updated_html = inject_into_html(html_content, explorer_page, css, js, nav_item)

    # Write updated HTML
    print(f"💾 Writing updated {OUTPUT_FILE}...")
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
        f.write(updated_html)

    # Print summary
    print()
    print("=" * 60)
    print("✅ GENERATION COMPLETE!")
    print("=" * 60)
    print()
    print(f"📁 Files indexed: {stats['total_files']}")
    print(f"📂 Directories: {stats['total_dirs']}")
    print(f"💾 Total size: {stats['total_size_formatted']}")
    print()
    print("📊 Files by category:")
    for cat, count in sorted(stats['by_category'].items(), key=lambda x: -x[1]):
        print(f"   {cat}: {count}")
    print()
    print(f"🌐 Open {OUTPUT_FILE} in your browser to view!")
    print()

    return 0


if __name__ == "__main__":
    exit(main())
