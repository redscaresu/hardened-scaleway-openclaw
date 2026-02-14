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
# Scoped to minimum required permissions for restic:
#   - BucketsRead: list bucket contents (restic snapshots, restic check)
#   - ObjectsRead: download objects (restic restore)
#   - ObjectsWrite: upload objects (restic backup)
#   - ObjectsDelete: remove old snapshots (restic forget --prune)
resource "scaleway_iam_policy" "backup" {
  count       = var.enable_backups ? 1 : 0
  name        = "${var.instance_name}-backup-policy"
  description = "Allow openclaw to read/write/delete backup objects only"

  application_id = scaleway_iam_application.backup[0].id

  rule {
    project_ids = [scaleway_instance_security_group.openclaw.project_id]
    permission_set_names = [
      "ObjectStorageBucketsRead",
      "ObjectStorageObjectsRead",
      "ObjectStorageObjectsWrite",
      "ObjectStorageObjectsDelete",
    ]
  }
}
