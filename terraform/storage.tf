# Object storage for backups (bucket created by bootstrap script)
# We just create IAM credentials here

# IAM application for backup access
resource "scaleway_iam_application" "backup" {
  count = var.enable_backups ? 1 : 0
  name  = "${var.instance_name}-backup-app"
}

# API key for backup application
resource "scaleway_iam_api_key" "backup" {
  count          = var.enable_backups ? 1 : 0
  application_id = scaleway_iam_application.backup[0].id
  description    = "API key for openclaw backups to object storage"
}

# Policy to allow access to backup bucket
resource "scaleway_iam_policy" "backup" {
  count       = var.enable_backups ? 1 : 0
  name        = "${var.instance_name}-backup-policy"
  description = "Allow openclaw to write backups to object storage"

  application_id = scaleway_iam_application.backup[0].id

  rule {
    permission_set_names = ["ObjectStorageFullAccess"]
    # Scope to specific bucket (requires bucket ARN)
  }
}
