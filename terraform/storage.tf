# Object storage for backups (bucket created by bootstrap script)
# We just create IAM credentials here

# IAM application for backup access
resource "scaleway_iam_application" "backup" {
  count = var.enable_backups ? 1 : 0
  name  = "${var.instance_name}-backup-app"
}

# API key for backup application
# NOTE: default_project_id is set to org ID because bootstrap creates buckets
# at the organization scope (Scaleway Object Storage default).
# S3 clients that don't support the @PROJECT_ID suffix need this to match
# the bucket's owner scope.
resource "scaleway_iam_api_key" "backup" {
  count              = var.enable_backups ? 1 : 0
  application_id     = scaleway_iam_application.backup[0].id
  description        = "API key for openclaw backups to object storage"
  default_project_id = scaleway_iam_application.backup[0].organization_id
}

# Policy to allow access to backup bucket
# Scoped to organization (bucket is org-owned, not project-scoped).
# Minimum permissions for restic:
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
    organization_id = scaleway_iam_application.backup[0].organization_id
    permission_set_names = [
      "ObjectStorageBucketsRead",
      "ObjectStorageObjectsRead",
      "ObjectStorageObjectsWrite",
      "ObjectStorageObjectsDelete",
    ]
  }
}
