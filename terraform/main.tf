# SSH key for initial access
resource "scaleway_account_ssh_key" "admin" {
  name       = "${var.instance_name}-admin-key"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

# Random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# Reserved public IP for initial SSH access (before Tailscale setup)
resource "scaleway_instance_ip" "public" {}

# Openclaw server instance
resource "scaleway_instance_server" "openclaw" {
  name  = var.instance_name
  type  = var.instance_type
  image = "ubuntu_noble" # Ubuntu 24.04 LTS
  zone  = var.zone

  # Public IP for initial SSH access (before Tailscale setup)
  # Use a reserved IP with routed=false so cloud-init can reach the metadata API (169.254.42.42)
  ip_id = scaleway_instance_ip.public.id

  # Use local storage for maximum security (data stays on instance)
  root_volume {
    size_in_gb = 20
  }

  # Cloud-init for initial provisioning
  user_data = {
    cloud-init = templatefile("${path.module}/cloud-init.yaml", {
      admin_username            = var.admin_username
      ssh_public_key            = file(pathexpand(var.ssh_public_key_path))
      tailscale_auth_key        = var.tailscale_auth_key
      signal_alert_number       = var.signal_alert_number
      openclaw_gateway_token    = var.openclaw_gateway_token
      anthropic_api_key         = var.anthropic_api_key
      openai_api_key            = var.openai_api_key
      telegram_bot_token        = var.telegram_bot_token
      github_token              = var.github_token
      brave_api_key             = var.brave_api_key
      openrouter_key            = var.openrouter_key
      openclaw_version          = var.openclaw_version
      openclaw_optimised_config = var.openclaw_optimised_config
      enable_browser_automation = var.enable_browser_automation
      squid_extra_domains       = var.squid_extra_domains
      backup_bucket             = var.backup_bucket_name
      aws_access_key            = var.enable_backups ? scaleway_iam_api_key.backup[0].access_key : ""
      aws_secret_key            = var.enable_backups ? scaleway_iam_api_key.backup[0].secret_key : ""
    })
  }

  # Attach security group
  security_group_id = scaleway_instance_security_group.openclaw.id

  tags = [
    "openclaw",
    "production",
    "managed-by-terraform"
  ]
}

# Security group (Scaleway's equivalent)
resource "scaleway_instance_security_group" "openclaw" {
  name                    = "${var.instance_name}-sg"
  inbound_default_policy  = "drop"
  outbound_default_policy = "accept"

  # SSH - only if public SSH is enabled (disable for Tailscale-only access)
  dynamic "inbound_rule" {
    for_each = var.enable_public_ssh ? (length(var.allowed_ssh_ips) > 0 ? var.allowed_ssh_ips : ["0.0.0.0/0"]) : []
    content {
      action   = "accept"
      port     = 22
      protocol = "TCP"
      ip_range = inbound_rule.value
    }
  }

  # Tailscale (UDP hole punching)
  inbound_rule {
    action   = "accept"
    port     = 41641
    protocol = "UDP"
  }

  # ICMP for ping (optional, helps debugging)
  inbound_rule {
    action   = "accept"
    protocol = "ICMP"
  }

  stateful = true
}
