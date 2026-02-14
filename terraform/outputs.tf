locals {
  ssh_cmd = var.enable_public_ssh ? (
    "ssh -i ~/.ssh/openclaw_ed25519 ${var.admin_username}@${scaleway_instance_ip.public.address}"
    ) : (
    "ssh ${var.admin_username}@<tailscale-hostname>  # Public SSH disabled, use Tailscale"
  )

  next_steps_public = <<-EOT

    1. Wait 5-10 mins for cloud-init + reboot to complete
    2. SSH in:
         ssh -i ~/.ssh/openclaw_ed25519 ${var.admin_username}@${scaleway_instance_ip.public.address}
    3. Verify cloud-init:    sudo cloud-init status
    4. Save backup password: sudo grep RESTIC_PASSWORD /root/.restic-env
    5. Verify Tailscale:     sudo tailscale status
    6. Link signal-cli:      sudo link-signal.sh
    7. Lock down SSH:        sudo ufw delete limit 22/tcp

    Full guide: see README.md -> Post-Deployment
  EOT

  next_steps_tailscale = <<-EOT

    1. Wait 5-10 mins for cloud-init + reboot to complete
    2. Check Tailscale admin for the new machine: https://login.tailscale.com/admin/machines
    3. SSH via Tailscale:
         ssh ${var.admin_username}@<tailscale-hostname>
    4. Verify cloud-init:    sudo cloud-init status
    5. Save backup password: sudo grep RESTIC_PASSWORD /root/.restic-env
    6. Link signal-cli:      sudo link-signal.sh

    Public SSH is disabled. All access is via Tailscale.
    Full guide: see README.md -> Post-Deployment
  EOT
}

output "instance_id" {
  description = "ID of the openclaw instance"
  value       = scaleway_instance_server.openclaw.id
}

output "instance_public_ip" {
  description = "Public IP address (for initial SSH setup)"
  value       = scaleway_instance_ip.public.address
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = local.ssh_cmd
}

output "backup_bucket" {
  description = "Name of the backup bucket"
  value       = var.backup_bucket_name
}

output "next_steps" {
  description = "Post-deployment checklist"
  value       = var.enable_public_ssh ? local.next_steps_public : local.next_steps_tailscale
}
