#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# test-with-mock.sh — Run terraform apply+destroy against mockway
# ──────────────────────────────────────────────

TF_DIR="$(cd "$(dirname "$0")/../terraform" && pwd)"
MOCKWAY_PID=""
TF_TEMP_DIR=""
OVERRIDE_FILE="$TF_DIR/backend_override.tf"

# Clean up stale override file from a previous interrupted run
if [[ -f "$OVERRIDE_FILE" ]]; then
  echo "WARNING: Removing stale $OVERRIDE_FILE from a previous run"
  rm -f "$OVERRIDE_FILE"
fi

cleanup() {
  if [[ -n "$MOCKWAY_PID" ]] && kill -0 "$MOCKWAY_PID" 2>/dev/null; then
    kill "$MOCKWAY_PID" 2>/dev/null || true
    wait "$MOCKWAY_PID" 2>/dev/null || true
  fi
  if [[ -n "$OVERRIDE_FILE" && -f "$OVERRIDE_FILE" ]]; then
    rm -f "$OVERRIDE_FILE"
  fi
  if [[ -n "$TF_TEMP_DIR" && -d "$TF_TEMP_DIR" ]]; then
    rm -rf "$TF_TEMP_DIR"
  fi
}
trap cleanup EXIT

# ── Find mockway binary ──
MOCKWAY_BIN=""
if [[ -n "${GOPATH:-}" && -x "$GOPATH/bin/mockway" ]]; then
  MOCKWAY_BIN="$GOPATH/bin/mockway"
elif [[ -n "${GOBIN:-}" && -x "$GOBIN/mockway" ]]; then
  MOCKWAY_BIN="$GOBIN/mockway"
elif command -v mockway &>/dev/null; then
  MOCKWAY_BIN="$(command -v mockway)"
else
  echo "ERROR: mockway binary not found in \$GOPATH/bin, \$GOBIN, or PATH" >&2
  echo "Run: make mockway-build" >&2
  exit 1
fi
echo "Using mockway: $MOCKWAY_BIN"

# ── Pick a free port ──
pick_free_port() {
  python3 -c 'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1]); s.close()'
}
PORT=$(pick_free_port)
echo "Starting mockway on port $PORT..."

# ── Start mockway ──
"$MOCKWAY_BIN" -port "$PORT" &
MOCKWAY_PID=$!

# ── Wait for mockway to be ready ──
echo -n "Waiting for mockway"
for i in $(seq 1 30); do
  if curl -sf "http://localhost:$PORT/mock/state" >/dev/null 2>&1; then
    echo " ready"
    break
  fi
  if ! kill -0 "$MOCKWAY_PID" 2>/dev/null; then
    echo " FAILED (process exited)"
    exit 1
  fi
  echo -n "."
  sleep 0.5
done

if ! curl -sf "http://localhost:$PORT/mock/state" >/dev/null 2>&1; then
  echo " FAILED (timeout)"
  exit 1
fi

# ── Configure environment for mock ──
export SCW_API_URL="http://localhost:$PORT"
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

TF_VARS=(
  -var 'tailscale_auth_key=tskey-auth-test-dummy'
  -var 'openclaw_gateway_token=test-gateway-token'
  -var 'signal_alert_number=+15551234567'
  -var 'backup_bucket_name=test-bucket'
)

# ── Terraform init ──
echo ""
echo "=== terraform init ==="
terraform -chdir="$TF_DIR" init -input=false -reconfigure

# ── Terraform apply ──
echo ""
echo "=== terraform apply ==="
terraform -chdir="$TF_DIR" apply \
  "${TF_VARS[@]}" \
  -auto-approve \
  -input=false

# ── Terraform destroy ──
echo ""
echo "=== terraform destroy ==="
terraform -chdir="$TF_DIR" destroy \
  "${TF_VARS[@]}" \
  -auto-approve \
  -input=false

echo ""
echo "=== PASS: apply + destroy succeeded ==="
