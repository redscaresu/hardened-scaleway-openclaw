# Hardened Scaleway Openclaw

[Just use a VPS bro](https://www.youtube.com/watch?v=40SnEd1RWUU)

Production-ready, security-hardened server infrastructure on [Scaleway](https://www.scaleway.com/) using Terraform. One command deploys a fully configured Ubuntu 24.04 instance with zero-trust networking, encrypted backups, intrusion detection, and Signal-based alerting.

Built for running [Openclaw](https://github.com/openclaw/openclaw), but the hardened base works for any workload.

**Cost:** ~EUR 10-15/month (Scaleway DEV1-S)

## What You Get

A single Scaleway instance with defense-in-depth security:

| Layer | Tools |
|---|---|
| **Network** | UFW firewall (default deny), Scaleway security groups, Tailscale zero-trust VPN, Squid outbound proxy (allowlist) |
| **SSH** | Key-only auth (ed25519), root login disabled, rate-limited, fail2ban |
| **Kernel** | SYN flood protection, anti-spoofing, restricted dmesg, hidden kernel pointers |
| **Monitoring** | AIDE file integrity checks, auditd syscall auditing, prometheus-node-exporter |
| **App** | Openclaw AI gateway on loopback:18789, Telegram bot integration, health-checked, optional headless Chrome (proxy-enforced) |
| **Alerts** | Signal messenger notifications for security events and blocked outbound requests |
| **Backups** | Nightly encrypted backups to S3 via restic (7 daily, 4 weekly, 12 monthly) |
| **Updates** | Unattended security patches with automatic reboot |
| **Secrets** | Metadata API blocked, no secrets in code, remote state in private S3 |

## Quick Start

### 1. Prerequisites

- [Scaleway account](https://console.scaleway.com/register) with payment method
- [Tailscale account](https://login.tailscale.com/start) (free tier) — create a `tag:openclaw` tag in [ACLs](https://login.tailscale.com/admin/acls) and generate an auth key with that tag so new instances auto-tag on join
- [Scaleway CLI](https://github.com/scaleway/scaleway-cli) and [Terraform](https://developer.hashicorp.com/terraform/install) (>= 1.0)

```bash
# macOS
brew install scaleway-cli terraform

# Generate SSH key
ssh-keygen -t ed25519 -C "openclaw-admin" -f ~/.ssh/openclaw_ed25519
```

### 2. Configure Scaleway

```bash
scw init
scw account project create name=openclaw description="Openclaw Infrastructure"
scw config set default-project-id=<PROJECT_ID>
```

### 3. Bootstrap & Deploy

```bash
# Create S3 buckets for state and backups
cd terraform/bootstrap
chmod +x init-remote-state.sh
./init-remote-state.sh
cd ..

# Configure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set admin_username, backup_bucket_name (from bootstrap output)
# Edit .env.terraform — set TF_VAR_tailscale_auth_key, TF_VAR_signal_alert_number,
#   TF_VAR_openclaw_gateway_token, TF_VAR_anthropic_api_key, TF_VAR_telegram_bot_token

# Deploy
source .env.terraform
terraform init
terraform plan
terraform apply
```

### 4. Post-Deploy Setup (after ~10-15 min for cloud-init + build)

```bash
# SSH in via Tailscale (hostname shown in terraform output)
tailscale ssh <admin_username>@<tailscale-hostname>

# Check cloud-init completed
sudo cloud-init status

# Save backup password (exists only on server — store it safely)
sudo grep RESTIC_PASSWORD /root/.restic-env

# Link Signal alerts (interactive — generates QR code to scan)
sudo link-signal.sh

# Pair Telegram bot (interactive — paste code from /start)
sudo pair-telegram.sh
```

> **Telegram pairing gotcha:** The gateway and CLI use different credential paths (`$STATE_DIR/credentials/` vs `$STATE_DIR/.openclaw/credentials/`). Running `openclaw pairing approve` directly will fail with "No pending pairing request found." Always use `sudo pair-telegram.sh` — it syncs the pending request from the gateway's path to the CLI's path, runs approval as the `openclaw` user, then syncs the result back.

## Architecture

```
                    ┌─────────────────────────────────────┐
                    │         Scaleway DEV1-S             │
                    │         Ubuntu 24.04 LTS            │
Tailscale ──────┐   │                                     │
  VPN (41641)   ├──►│  ┌──────────┐  ┌────────────────┐   │
                    │  │ UFW      │  │ fail2ban       │   │
                    │  │ firewall │  │ brute-force    │   │
                    │  └──────────┘  └────────────────┘   │
                    │  ┌──────────┐  ┌────────────────┐   │
                    │  │ Openclaw │  │ Telegram bot   │   │
                    │  │ gateway  │  │ integration    │   │
                    │  │ :18789   │  │                │   │
                    │  └──────────┘  └────────────────┘   │
                    │  ┌──────────┐  ┌────────────────┐   │
                    │  │ Squid    │──│ Allowlist-only │   │
                    │  │ proxy    │  │ outbound HTTP  │   │
                    │  └──────────┘  └────────────────┘   │
                    │  ┌──────────┐  ┌────────────────┐   │
                    │  │ AIDE     │  │ auditd         │   │
                    │  │ integrity│  │ syscall audit  │   │
                    │  └──────────┘  └────────────────┘   │
                    │  ┌──────────┐  ┌────────────────┐   │
                    │  │ restic   │──│ Scaleway S3    │   │
                    │  │ backups  │  │ (encrypted)    │   │
                    │  └──────────┘  └────────────────┘   │
                    │  ┌──────────┐  ┌────────────────┐   │
                    │  │signal-cli│  │ node-exporter  │   │
                    │  │ alerts   │  │ metrics        │   │
                    │  └──────────┘  └────────────────┘   │
                    └─────────────────────────────────────┘
```

## Openclaw Integration

Openclaw is deployed automatically. The gateway binds to loopback only — access it via SSH tunnel:

```bash
# Open SSH tunnel (keep this terminal open)
ssh -L 18789:127.0.0.1:18789 <admin_username>@<tailscale-hostname>

# Open in browser
open http://localhost:18789
```

Post-deploy setup:
1. **Link Signal** — `sudo link-signal.sh` (scan QR code with Signal app)
2. **Pair Telegram** — `sudo pair-telegram.sh` (send `/start` to your bot, paste the code)

## Browser Automation

Optional headless Chrome for openclaw browser automation (e.g. navigating eBay, Vinted, Amazon listings). Disabled by default.

```hcl
# terraform.tfvars
enable_browser_automation = true
```

### How it works

Chrome runs as the `openclaw` user, which means **all browser traffic is forced through the squid proxy** — the same allowlist and iptables rules that govern openclaw's other outbound requests apply to the browser. Domains not on the allowlist get a `403 TCP_DENIED` from squid.

The browser config is written to `/var/lib/openclaw/openclaw.json`:

```json
{
  "browser": {
    "headless": true,
    "noSandbox": true,
    "executablePath": "/usr/bin/google-chrome-stable"
  }
}
```

### Adding domains for target sites

Browser automation needs CDN domains (images, scripts) in addition to the main site domain. Add these to `TF_VAR_squid_extra_domains` in `.env.terraform`:

| Site | Domains needed |
|---|---|
| eBay | `.ebay.com`, `.ebay.co.uk`, `.ebayimg.com`, `.ebaystatic.com` |
| Vinted | `.vinted.co.uk`, `.vinted.net` |
| Amazon | `.amazon.co.uk`, `.ssl-images-amazon.com`, `.media-amazon.com` |
| Gumtree | `.gumtree.com`, `.classistatic.com` |

If pages render incorrectly, check squid access logs for `TCP_DENIED` entries and add the missing domains:

```bash
sudo grep TCP_DENIED /var/log/squid/access.log | tail -20
```

### Live server install (without redeploy)

```bash
# Install Chrome
sudo apt-get update && sudo apt-get install -y google-chrome-stable

# Or download the .deb directly
curl -fsSL -o /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo apt-get install -y /tmp/chrome.deb

# Add CDN domains to squid allowlist
echo '.ebayimg.com' | sudo tee -a /etc/squid/allowed-domains.txt
sudo systemctl reload squid

# Restart openclaw to pick up config changes
sudo systemctl restart openclaw
```

## Backup & Restore

Nightly encrypted backups to Scaleway S3 via [restic](https://restic.net/) (2am daily). Backs up all openclaw state, config, credentials, workspace files, and databases.

**What's backed up:** `/var/lib/openclaw/` (all state, config, sessions, databases), `/etc/ssh/sshd_config.d/`, `/etc/sysctl.d/`, `/etc/openclaw-alerts.conf`

**Retention:** 7 daily, 4 weekly, 12 monthly snapshots.

### Save your backup password

The restic password is generated on first boot and exists **only on the server**. If lost, backups are unrecoverable. Save it immediately after deploy:

```bash
sudo grep RESTIC_PASSWORD /root/.restic-env
```

### Before a destroy/rebuild

Trigger a fresh backup to capture changes since the last nightly run:

```bash
sudo /usr/local/bin/backup-server.sh
```

Verify it completed:

```bash
sudo bash -c 'source /root/.restic-env && restic snapshots'
```

### Restore after rebuild

After `terraform apply` and cloud-init completes on the new instance:

> **Password mismatch:** Each new instance generates a fresh restic password. To restore from a previous instance's backups, you must use the **old** password (the one you saved). Replace the new password in `/root/.restic-env` before restoring, or pass it via `RESTIC_PASSWORD`.

```bash
# Replace the new instance's restic password with the saved one
sudo sed -i 's|RESTIC_PASSWORD=.*|RESTIC_PASSWORD="<your-saved-password>"|' /root/.restic-env

# Verify access to old backups
sudo bash -c 'source /root/.restic-env && restic snapshots'

# Stop the gateway, restore, fix ownership, restart
sudo systemctl stop openclaw
sudo bash -c 'source /root/.restic-env && restic restore latest --target / --include /var/lib/openclaw/'
sudo chown -R openclaw:openclaw /var/lib/openclaw/
sudo systemctl start openclaw

# Optional: restore system configs (SSH hardening, sysctl, alert config)
sudo bash -c 'source /root/.restic-env && restic restore latest --target / --include /etc/ssh/sshd_config.d/ --include /etc/sysctl.d/ --include /etc/openclaw-alerts.conf'
```

### What needs re-pairing after rebuild

Signal-cli and Telegram are not backed up — they require interactive pairing:

1. **Signal** — `sudo link-signal.sh` (scan QR code)
2. **Telegram** — `sudo pair-telegram.sh` (paste code from `/start`)

Tailscale re-authenticates automatically via the auth key in Terraform.

## Local Testing

Validate Terraform plans offline using [Mockway](https://github.com/redscaresu/mockway), a stateful mock of the Scaleway API. No real credentials or infrastructure needed.

**Prerequisites:** Go toolchain, mockway repo cloned as a sibling directory (`../mockway`)

```bash
make test-plan                            # Build mockway, run terraform plan against it
make test-plan MOCKWAY_SRC=/other/path    # Use a different mockway checkout
make fmt                                  # terraform fmt
make validate                             # terraform validate (needs .env.terraform)
```

`make test-plan` catches:
- Cloud-init template rendering errors (variable mismatches, bad HCL template syntax)
- HCL syntax and type errors
- Resource planning failures against all Scaleway resource types
- Missing or misconfigured variable definitions

## File Structure

```
├── README.md                              # This file
├── Makefile                               # fmt, validate, test-plan targets
├── scripts/
│   └── test-with-mock.sh                  # Runs terraform plan against mockway
└── terraform/
    ├── README.md                          # Detailed setup, security docs, troubleshooting
    ├── bootstrap/
    │   └── init-remote-state.sh           # Run first — creates S3 buckets
    ├── providers.tf                       # Scaleway provider config
    ├── variables.tf                       # Input variable definitions
    ├── terraform.tfvars.example           # Template — copy to terraform.tfvars
    ├── main.tf                            # Instance + security group
    ├── storage.tf                         # IAM for backup credentials
    ├── outputs.tf                         # IP, SSH command, next steps
    ├── cloud-init.yaml                    # Server provisioning template
    └── .gitignore                         # Keeps credentials out of git
```

## Documentation

See [`terraform/README.md`](terraform/README.md) for:
- Full security measures documentation
- Detailed setup instructions
- Post-deployment verification checklist
- Prometheus metrics access
- Automated jobs schedule
- Troubleshooting guide

## Contributing

Contributions welcome. Please open an issue to discuss changes before submitting a PR.

- Run `make test-plan` to validate against mockway before deploying
- Run `make fmt` before committing
- Never commit files containing credentials

## License

MIT
