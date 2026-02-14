# Hardened Scaleway Openclaw

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
| **App** | Openclaw AI gateway on loopback:18789, Telegram bot integration, health-checked |
| **Alerts** | Signal messenger notifications for security events and blocked outbound requests |
| **Backups** | Nightly encrypted backups to S3 via restic (7 daily, 4 weekly, 12 monthly) |
| **Updates** | Unattended security patches with automatic reboot |
| **Secrets** | Metadata API blocked, no secrets in code, remote state in private S3 |

## Quick Start

### 1. Prerequisites

- [Scaleway account](https://console.scaleway.com/register) with payment method
- [Tailscale account](https://login.tailscale.com/start) (free tier)
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

## File Structure

```
├── README.md                              # This file
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

- Run `terraform fmt` before committing
- Run `terraform validate` to check for errors
- Never commit files containing credentials
- Test with `terraform plan` before applying

## License

MIT
