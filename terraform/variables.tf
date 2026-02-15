variable "zone" {
  description = "Scaleway availability zone (overrides CLI config default)"
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

variable "enable_public_ssh" {
  description = "Allow SSH via public IP (set to false for Tailscale-only access)"
  type        = bool
  default     = true
}

variable "allowed_ssh_ips" {
  description = "IP addresses allowed to SSH (CIDR notation, only used when enable_public_ssh = true)"
  type        = list(string)
  default     = [] # Empty = allow from anywhere (before Tailscale setup)
}

variable "tailscale_auth_key" {
  description = "Tailscale authentication key (get from https://login.tailscale.com/admin/settings/keys)"
  type        = string
  sensitive   = true
}

variable "openclaw_gateway_token" {
  description = "Auth token for openclaw gateway web UI (required when binding beyond loopback)"
  type        = string
  sensitive   = true
}

variable "anthropic_api_key" {
  description = "Anthropic API key for openclaw"
  type        = string
  sensitive   = true
  default     = ""
}

variable "openai_api_key" {
  description = "OpenAI API key for openclaw"
  type        = string
  sensitive   = true
  default     = ""
}

variable "telegram_bot_token" {
  description = "Telegram bot token for openclaw"
  type        = string
  sensitive   = true
  default     = ""
}

variable "github_token" {
  description = "GitHub personal access token for openclaw"
  type        = string
  sensitive   = true
  default     = ""
}

variable "deepseek_api_key" {
  description = "DeepSeek API key for openclaw (fallback/subagent model)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "openclaw_version" {
  description = "Openclaw version tag to install (e.g. v2026.2.14)"
  type        = string
  default     = "v2026.2.14"
}

variable "squid_extra_domains" {
  description = "Additional domains to allow through the squid proxy (e.g. .example.com)"
  type        = list(string)
  sensitive   = true
  default     = []
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
