#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# test-plan.sh — Run terraform plan with dummy credentials (no API needed)
# ──────────────────────────────────────────────

TF_DIR="$(cd "$(dirname "$0")/../terraform" && pwd)"
TF_TEMP_DIR=""
OVERRIDE_FILE="$TF_DIR/backend_override.tf"

# Clean up stale override file from a previous interrupted run
if [[ -f "$OVERRIDE_FILE" ]]; then
  echo "WARNING: Removing stale $OVERRIDE_FILE from a previous run"
  rm -f "$OVERRIDE_FILE"
fi

cleanup() {
  if [[ -n "$OVERRIDE_FILE" && -f "$OVERRIDE_FILE" ]]; then
    rm -f "$OVERRIDE_FILE"
  fi
  if [[ -n "$TF_TEMP_DIR" && -d "$TF_TEMP_DIR" ]]; then
    rm -rf "$TF_TEMP_DIR"
  fi
}
trap cleanup EXIT

# ── Dummy Scaleway credentials (plan never hits the API) ──
export SCW_API_URL="http://localhost:1"
export SCW_ACCESS_KEY="SCWXXXXXXXXXXXXXXXXX"
export SCW_SECRET_KEY="00000000-0000-0000-0000-000000000000"
export SCW_DEFAULT_PROJECT_ID="00000000-0000-0000-0000-000000000000"
export SCW_DEFAULT_ORGANIZATION_ID="00000000-0000-0000-0000-000000000000"
export SCW_DEFAULT_REGION="fr-par"
export SCW_DEFAULT_ZONE="fr-par-1"

# Use a temp directory for terraform data to avoid polluting real .terraform/
TF_TEMP_DIR="$(mktemp -d)"
export TF_DATA_DIR="$TF_TEMP_DIR"

# Override the S3 backend with local backend using temp state path (cleaned up by trap)
cat > "$OVERRIDE_FILE" <<EOF
terraform {
  backend "local" {
    path = "$TF_TEMP_DIR/test.tfstate"
  }
}
EOF

# ── Terraform init ──
echo "=== terraform init ==="
terraform -chdir="$TF_DIR" init -input=false

# ── Terraform plan ──
echo ""
echo "=== terraform plan ==="
terraform -chdir="$TF_DIR" plan \
  -var 'tailscale_auth_key=tskey-auth-test-dummy' \
  -var 'openclaw_gateway_token=test-gateway-token' \
  -var 'signal_alert_number=+15551234567' \
  -var 'backup_bucket_name=test-bucket' \
  -input=false \
  -detailed-exitcode \
  && PLAN_EXIT=0 || PLAN_EXIT=$?

# -detailed-exitcode: 0=no changes, 1=error, 2=changes present
echo ""
if [[ $PLAN_EXIT -eq 0 || $PLAN_EXIT -eq 2 ]]; then
  echo "=== PASS: terraform plan succeeded ==="
  exit 0
else
  echo "=== FAIL: terraform plan returned errors ==="
  exit 1
fi
