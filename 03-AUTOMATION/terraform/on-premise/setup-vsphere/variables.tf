# =============================================================================
# vSphere Connection Variables
# Set these via GitHub Secrets as TF_VAR_<variable_name>
# =============================================================================

variable "vsphere_user" {
  description = "vSphere username for authentication"
  type        = string
  sensitive   = true
}

variable "vsphere_password" {
  description = "vSphere password for authentication"
  type        = string
  sensitive   = true
}

variable "vsphere_server" {
  description = "vSphere server hostname or IP address"
  type        = string
}

variable "vsphere_allow_unverified_ssl" {
  description = "Allow unverified SSL certificates (for self-signed certs)"
  type        = bool
  default     = true
}

# =============================================================================
# vSphere Infrastructure Variables
# =============================================================================

variable "datacenter_name" {
  description = "Name of the vSphere datacenter"
  type        = string
  default     = "Datacenter"
}