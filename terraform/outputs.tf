output "instance_id" {
  description = "ID of the openclaw instance"
  value       = scaleway_instance_server.openclaw.id
}

output "instance_public_ip" {
  description = "Public IP address (for initial SSH setup)"
  value       = scaleway_instance_server.openclaw.public_ips.0.address
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i ~/.ssh/openclaw_ed25519 ${var.admin_username}@${scaleway_instance_server.openclaw.public_ips.0.address}"
}

output "backup_bucket" {
  description = "Name of the backup bucket"
  value       = var.backup_bucket_name
}

output "next_steps" {
  description = "Post-deployment checklist"
  value       = <<-EOT

    1. Wait 5-10 mins for cloud-init + reboot to complete
    2. SSH in:
         ssh -i ~/.ssh/openclaw_ed25519 ${var.admin_username}@${scaleway_instance_server.openclaw.public_ips.0.address}
    3. Verify cloud-init:    sudo cloud-init status
    4. Save backup password: sudo grep RESTIC_PASSWORD /root/.restic-env
    5. Verify Tailscale:     sudo tailscale status
    6. Link signal-cli:      sudo signal-cli link -n "openclaw-server"
    7. Test alerts:          sudo /usr/local/bin/send-alert.sh "test"
    8. Lock down SSH:        sudo ufw delete limit 22/tcp

    Full guide: see README.md -> Post-Deployment
  EOT
}
