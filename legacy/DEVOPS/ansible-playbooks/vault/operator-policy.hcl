# 1. Manage Secrets (Create, Read, Update, List... BUT NO DELETE)
path "secret/*" {
  capabilities = ["create", "read", "update", "list"] 
  # Removed "delete" -> They cannot remove secrets.
  # Removed "sudo"   -> They cannot force dangerous actions.
}

# 2. Allow them to see secret metadata (versions), but NOT delete the history
path "secret/metadata/*" {
  capabilities = ["list", "read"]
}

# 3. Check Health (Read-only)
path "sys/health" {
  capabilities = ["read"]
}

# 4. Standard System Read Access
path "sys/mounts" {
  capabilities = ["read", "list"]
}