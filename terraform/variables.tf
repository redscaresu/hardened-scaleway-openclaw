variable "region" {
  description = "Scaleway region"
  type        = string
  default     = "fr-par"
}

variable "zone" {
  description = "Scaleway availability zone"
  type        = string
  default     = "fr-par-1"
}

variable "instance_type" {
  description = "Instance type for openclaw server"
  type        = string
  default     = "DEV1-S" # 2 vCPU, 2GB RAM, 20GB SSD
}

variable "instance_name" {
  description = "Name of the openclaw instance"
  type        = string
  default     = "openclaw-prod"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key for initial access"
  type        = string
  default     = "~/.ssh/openclaw_ed25519.pub"
}

variable "admin_username" {
  description = "Admin username (non-root)"
  type        = string
  default     = "admin"
}

variable "allowed_ssh_ips" {
  description = "IP addresses allowed to SSH (CIDR notation)"
  type        = list(string)
  default     = [] # Empty = allow from anywhere (before Tailscale setup)
}

variable "tailscale_auth_key" {
  description = "Tailscale authentication key (get from https://login.tailscale.com/admin/settings/keys)"
  type        = string
  sensitive   = true
}

variable "openclaw_api_key" {
  description = "Anthropic/OpenAI API key for openclaw (not needed until openclaw is enabled in cloud-init)"
  type        = string
  sensitive   = true
  default     = "" # Set in terraform.tfvars when enabling openclaw
}

variable "signal_alert_number" {
  description = "Signal phone number for alerts (E.164 format, e.g. +15551234567)"
  type        = string
}

variable "enable_backups" {
  description = "Enable automated backups to object storage"
  type        = bool
  default     = true
}

variable "backup_bucket_name" {
  description = "Name of S3 bucket for backups (created by bootstrap script)"
  type        = string
  # No default — set in terraform.tfvars after running bootstrap
}
