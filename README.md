# Hardened Scaleway Openclaw

Production-ready, security-hardened server infrastructure on [Scaleway](https://www.scaleway.com/) using Terraform. One command deploys a fully configured Ubuntu 24.04 instance with zero-trust networking, encrypted backups, intrusion detection, and Signal-based alerting.

Built for running [Openclaw](https://github.com/redscaresu/openclaw), but the hardened base works for any workload.

**Cost:** ~EUR 10-15/month (Scaleway DEV1-S)

## What You Get

A single Scaleway instance with defense-in-depth security:

| Layer | Tools |
|---|---|
| **Network** | UFW firewall (default deny), Scaleway security groups, Tailscale zero-trust VPN |
| **SSH** | Key-only auth (ed25519), root login disabled, rate-limited, fail2ban |
| **Kernel** | SYN flood protection, anti-spoofing, restricted dmesg, hidden kernel pointers |
| **Monitoring** | AIDE file integrity checks, auditd syscall auditing, prometheus-node-exporter |
| **Alerts** | Signal messenger notifications for security events |
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

# Deploy
source .env.terraform
terraform init
terraform plan    # prompted for tailscale_auth_key and signal_alert_number
terraform apply
```

### 4. Verify (after ~5-10 min for cloud-init)

```bash
# SSH in (command shown in terraform output)
ssh -i ~/.ssh/openclaw_ed25519 <admin_username>@<public_ip>

# Check cloud-init completed
sudo cloud-init status

# Save backup password (exists only on server — store it safely)
sudo grep RESTIC_PASSWORD /root/.restic-env

# Verify Tailscale
sudo tailscale status

# Lock down public SSH once Tailscale works
sudo ufw delete limit 22/tcp
```

## Architecture

```
                    ┌─────────────────────────────────────┐
                    │         Scaleway DEV1-S              │
                    │         Ubuntu 24.04 LTS             │
Internet ──SSH──┐   │                                     │
  (temp)        │   │  ┌──────────┐  ┌────────────────┐   │
                ├──►│  │ UFW      │  │ fail2ban       │   │
                    │  │ firewall │  │ brute-force    │   │
Tailscale ──────┐   │  └──────────┘  │ protection     │   │
  VPN (41641)   ├──►│               └────────────────┘   │
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

## Enabling Openclaw

The base infrastructure deploys without the application — verify hardening first. To add Openclaw:

1. Uncomment all `OPENCLAW:` sections in `terraform/cloud-init.yaml`
2. Add `openclaw_api_key` to the `templatefile()` params in `terraform/main.tf`
3. Set `openclaw_api_key` in `terraform.tfvars`
4. Run `terraform apply` (recreates the instance)

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
