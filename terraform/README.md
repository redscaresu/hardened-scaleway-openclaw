# Terraform Configuration

Detailed setup, security documentation, and operational guide. For a quick overview, see the [root README](../README.md).

## What Gets Deployed

| Component | Purpose |
|---|---|
| **Scaleway DEV1-S** | Ubuntu 24.04 LTS instance (2 vCPU, 2GB RAM, 20GB SSD) |
| **Squid proxy** | Allowlist-only outbound HTTP/HTTPS filtering |
| **Tailscale** | Zero-trust VPN with SSH access |
| **UFW** | Firewall — rate-limited SSH (22/tcp) and Tailscale (41641/udp) only |
| **fail2ban** | Brute-force SSH protection |
| **signal-cli** | Signal messenger alerts (JVM version, linked as secondary device) |
| **restic** | Encrypted nightly backups to Scaleway S3 |
| **AIDE** | File integrity monitoring (nightly scan) |
| **auditd** | System call auditing |
| **unattended-upgrades** | Automatic security patches with auto-reboot at 3am |
| **prometheus-node-exporter** | System metrics |

### Security Measures

**Network**
- UFW firewall — default deny inbound, only SSH (22/tcp rate-limited) and Tailscale (41641/udp) allowed
- SSH rate-limited at firewall level (6 connections / 30 seconds) before fail2ban even sees it
- fail2ban SSH jail — bans IP after 3 failed attempts in 10 minutes (1 hour ban)
- Tailscale zero-trust VPN — public SSH can be removed once Tailscale is connected
- Scaleway security group — drop all inbound except SSH, Tailscale, ICMP
- Squid outbound proxy — allowlist-only HTTP/HTTPS filtering (see [Outbound Proxy](#outbound-proxy) below)

**SSH**
- Root login disabled
- Password authentication disabled, SSH key only (ed25519)
- Max 3 auth attempts per connection
- Idle timeout: 5 minutes (300s interval, 2 max count)
- X11 forwarding disabled
- Only the admin user is allowed to SSH (`AllowUsers`)

**Kernel**
- SYN flood protection (`tcp_syncookies`, `tcp_max_syn_backlog`, `tcp_synack_retries`)
- Reverse path filtering (anti-spoofing)
- ICMP redirects ignored
- Source-routed packets rejected
- Martian packets logged
- Broadcast ping ignored
- `dmesg` restricted to root
- Kernel pointers hidden (`kptr_restrict = 2`)
- IP forwarding enabled (required by Tailscale)

**Monitoring & Integrity**
- AIDE file integrity monitoring — nightly scan, alerts on changes via Signal
- auditd system call auditing with custom rules for sudo, su, passwd, SSH config, firewall, and cron changes
- Audit rules are immutable (`-e 2`) — require reboot to modify, preventing runtime tampering
- prometheus-node-exporter for system metrics

**Privilege Separation**
- signal-cli runs as a dedicated `signal` user (not root) — limits blast radius of any signal-cli vulnerability
- signal-cli data stored in `/var/lib/signal-cli/` with `chmod 700`
- Scoped sudoers: only root can invoke signal-cli as the signal user (`/etc/sudoers.d/signal-cli`)
- Admin user has `NOPASSWD` sudo — standard for cloud VMs where SSH key is the authentication boundary. Tailscale SSH adds a second authentication factor (`check` mode requires browser re-auth)

**Updates**
- Unattended security upgrades enabled (security repos only, not all packages)
- Automatic reboot at 3am if kernel update requires it

**Secrets**
- No secrets in committed files — `terraform.tfvars` and `.env.terraform` are gitignored
- Sensitive variables (`tailscale_auth_key`, `signal_alert_number`, API keys, tokens, `squid_extra_domains`) passed via environment variables from `.env.terraform` (gitignored, chmod 600)
- Scaleway metadata API (`169.254.42.42`) blocked after provisioning via iptables — prevents any process from reading cloud-init secrets
- Metadata API block persisted across reboots via UFW `before.rules` (see [Metadata API Blocking](#metadata-api-blocking) for timing details)
- Terraform state stored remotely in a private, versioned S3 bucket — contains secrets, access controlled via Scaleway IAM
- Restic backup password generated once on first boot, scrubbed from cloud-init logs — must be saved externally

**Backups**
- Nightly encrypted backups of system configs to Scaleway S3 via restic
- Retention: 7 daily, 4 weekly, 12 monthly snapshots
- Repository integrity checked after each backup
- Dedicated IAM credentials scoped to backup bucket only (read/write/delete objects — no bucket management)

**Log Management**
- Custom logrotate config for squid access logs (weekly, 12 weeks retained, compressed)
- All alert scripts log to syslog via `logger` (managed by system logrotate)
- Squid access log tracks all allowed and denied requests

### Openclaw App

The [Openclaw](https://github.com/openclaw/openclaw) AI gateway is deployed automatically. It binds to loopback:18789 (access via SSH tunnel) with Telegram bot integration. Post-deploy, run `sudo link-signal.sh` and `sudo pair-telegram.sh`.

## Prerequisites

**Accounts:**
- [Scaleway account](https://console.scaleway.com/register) with payment method
- [Tailscale account](https://login.tailscale.com/start) (free tier)

**Tools:**
- [Scaleway CLI](https://github.com/scaleway/scaleway-cli) (`scw`)
- [Terraform](https://developer.hashicorp.com/terraform/install) (>= 1.0)

**macOS:**
```bash
brew install scaleway-cli terraform
```

**Linux:**
```bash
curl -s https://raw.githubusercontent.com/scaleway/scaleway-cli/master/scripts/get.sh | sh
# Terraform: https://developer.hashicorp.com/terraform/install
```

**SSH key** — generate a dedicated key pair for this server:
```bash
ssh-keygen -t ed25519 -C "openclaw-admin" -f ~/.ssh/openclaw_ed25519
```
This creates `~/.ssh/openclaw_ed25519` (private key — keep secret) and `~/.ssh/openclaw_ed25519.pub` (public key — safe to share).

**Tailscale** — install on your local machine from https://tailscale.com/download and log in. Then:

1. Add the ACL rules (see [Configure Tailscale SSH](#5-configure-tailscale-ssh) for the full policy)
2. Generate an auth key from https://login.tailscale.com/admin/settings/keys — check "Reusable", optionally "Ephemeral", and **assign the `tag:openclaw` tag** so the server auto-tags on join

You'll be prompted for the auth key during `terraform plan/apply`.

## Setup

### 1. Configure Scaleway CLI

Get API credentials from https://console.scaleway.com/iam/api-keys (generate a new key).

```bash
scw init
```

Create a dedicated project for isolation:

```bash
scw account project create name=openclaw description="Openclaw Infrastructure"

# Set as default
scw account project list | grep openclaw
scw config set default-project-id=<PROJECT_ID>
```

### 2. Bootstrap Remote State

This creates S3 buckets for Terraform state and server backups.

```bash
cd terraform/bootstrap
chmod +x init-remote-state.sh
./init-remote-state.sh
cd ..
```

This creates (with a unique suffix derived from your Scaleway project ID):
- `hso-tfstate-XXXXXXXX` — Terraform state (versioned)
- `hso-backups-XXXXXXXX` — encrypted server backups (restic)
- `backend-config.tf` — auto-generated backend config (gitignored)
- `.env.terraform` — Scaleway credentials (gitignored, chmod 600)

Note the backup bucket name from the output — you'll need it in the next step.

Verify:
```bash
scw object bucket list
```

### 3. Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values. At minimum set:
- `admin_username` — your username on the server
- `ssh_public_key_path` — path to your public key
- `backup_bucket_name` — the backup bucket name output by the bootstrap script
- `enable_public_ssh` — set to `false` for Tailscale-only access from first boot (no public SSH ever exposed)

Edit `.env.terraform` (created by the bootstrap script) and fill in the sensitive variables at the bottom:
- `TF_VAR_tailscale_auth_key` — from prerequisites
- `TF_VAR_signal_alert_number` — your phone number in E.164 format (e.g. `+15551234567`)
- `TF_VAR_openclaw_gateway_token` — generate with `openssl rand -hex 32`
- `TF_VAR_anthropic_api_key` — from https://console.anthropic.com/settings/keys
- `TF_VAR_telegram_bot_token` — from [@BotFather](https://t.me/botfather) on Telegram
- `TF_VAR_github_token` — from GitHub > Settings > Developer settings > Personal access tokens
- `TF_VAR_openrouter_key` — from https://openrouter.ai/keys (required for primary model, subagents, and heartbeat via OpenRouter)
- `TF_VAR_squid_extra_domains` — JSON list of extra proxy domains (e.g. `'[".example.com"]'`)

These are read automatically by Terraform via `source .env.terraform`. The file is gitignored and chmod 600.

### 4. Deploy

```bash
source .env.terraform
terraform init
terraform plan
terraform apply
```

Terraform will output the public IP and SSH command.

## Post-Deployment

The server runs cloud-init on first boot then reboots. Wait ~5-10 minutes before connecting.

### Tailscale-Only Mode (`enable_public_ssh = false`)

If you deployed with `enable_public_ssh = false`, the server **never** had a public SSH port. Connect via Tailscale only:

1. Check https://login.tailscale.com/admin/machines for the new machine
2. SSH via Tailscale: `ssh <admin_username>@<tailscale-hostname>`
3. Skip step 8 below (public SSH is already disabled)

### 1. SSH In

```bash
# If public SSH is enabled:
ssh -i ~/.ssh/openclaw_ed25519 <admin_username>@<public_ip>

# If Tailscale-only:
ssh <admin_username>@<tailscale-hostname>
```

If connection refused, the server is still rebooting — wait and retry.

### 2. Verify Cloud-Init

```bash
sudo cloud-init status                    # should say "done"
sudo tail -50 /var/log/cloud-init-output.log  # check for errors
```

### 3. Save Restic Backup Password

The backup password is auto-generated on first boot. It exists **only on the server**. Save it somewhere safe — without it, backups are unrecoverable.

```bash
sudo grep RESTIC_PASSWORD /root/.restic-env
```

### 4. Verify Hardening

```bash
# Firewall
sudo ufw status verbose

# SSH config
sudo sshd -T | grep -E 'permitrootlogin|passwordauthentication|maxauthtries'

# Kernel hardening
sudo sysctl net.ipv4.ip_forward net.ipv4.tcp_syncookies kernel.dmesg_restrict

# Metadata API blocked
curl -s --max-time 2 http://169.254.42.42/conf && echo "EXPOSED" || echo "Blocked (good)"

# Services
sudo systemctl status fail2ban auditd prometheus-node-exporter unattended-upgrades
```

### 5. Configure Tailscale SSH

Tailscale replaces public SSH access. After initial setup over the public IP, you'll switch to SSH over Tailscale's private network and close the public port.

**Verify Tailscale is connected:**
```bash
sudo tailscale status
```
Note the Tailscale IP (100.x.x.x).

**Configure Tailscale ACLs** — go to https://login.tailscale.com/admin/acls and add an SSH rule:

```json
"ssh": [
    {
        "src":    ["autogroup:member"],
        "dst":    ["tag:openclaw"],
        "users":  ["autogroup:nonroot"],
        "action": "check",
    },
],
```

Also add a tag owner entry (if not already present):
```json
"tagOwners": {"tag:openclaw": ["autogroup:admin"]},
```

If you generated the auth key with `tag:openclaw` assigned (recommended), the server auto-tags on join — no manual tagging needed.

- `check` mode requires browser re-authentication before granting SSH — more secure than `accept`
- `autogroup:nonroot` prevents root SSH, matching the server-side hardening
- The tag scopes SSH access to only your openclaw server

**Test from your local machine** (must have [Tailscale installed](https://tailscale.com/download) and logged in):
```bash
ssh -i ~/.ssh/openclaw_ed25519 <admin_username>@<tailscale_ip>
```

### 6. Link signal-cli

signal-cli is installed but needs linking to your Signal account before alerts work. See [Signal Alerts](#signal-alerts) for full details.

```bash
sudo link-signal.sh
```

### 7. Test Backup

```bash
sudo /usr/local/bin/backup-server.sh
sudo journalctl -t restic-backup --no-pager
```

### 8. Lock Down Public SSH

Once Tailscale SSH works (step 5), remove the public SSH firewall rule. After this, the server has no public SSH port — the only way in is through your Tailscale network.

```bash
sudo ufw delete limit 22/tcp
```

## Accessing Prometheus Metrics

prometheus-node-exporter listens on port 9100 but UFW blocks it from external access. Use an SSH tunnel over Tailscale:

```bash
ssh -i ~/.ssh/openclaw_ed25519 -L 9100:localhost:9100 <admin_username>@<tailscale_ip>
# Then open http://localhost:9100/metrics in your browser
```

If you run Prometheus/Grafana on another Tailscale node and want direct access, allow port 9100 over the Tailscale interface only:

```bash
sudo ufw allow in on tailscale0 to any port 9100 proto tcp
```

## Signal Alerts

Server events are sent to your phone via [Signal](https://signal.org/) using [signal-cli](https://github.com/AsamK/signal-cli). This gives you real-time notifications without relying on email infrastructure or third-party monitoring services.

### What Gets Alerted

| Event | Script | Schedule |
|---|---|---|
| Squid blocked outbound requests | `squid-denied-alert.sh` | Every 5 minutes |
| Restic backup completed | `backup-server.sh` | Nightly 2am |
| AIDE file integrity changes | `aide-check.sh` | Nightly 3am |
| Server provisioning complete | cloud-init `runcmd` | First boot |

All alerts go through `/usr/local/bin/send-alert.sh`, which reads the sender/recipient config from `/etc/openclaw-alerts.conf`. If signal-cli isn't linked yet, alerts fall back to syslog.

### How It Works

signal-cli runs as a dedicated `signal` system user (not root) for privilege separation. It's linked as a **secondary device** on your existing Signal account — no separate phone number needed. Messages appear in your **"Note to Self"** conversation (since sender and recipient are the same number).

```
Server event → send-alert.sh → sudo -u signal signal-cli → Signal servers → your phone
```

The JVM version of signal-cli is used (not the native GraalVM binary) because the native binary hangs indefinitely on CDSI contact refresh. The JVM version handles this gracefully.

**Security:** To revoke server access to your Signal account, open Signal on your phone > Settings > Linked Devices and remove the server's device. This immediately prevents the server from sending or receiving messages.

### Prerequisites

- A [Signal account](https://signal.org/) on your phone
- `qrencode` on your local machine for QR code scanning (optional — `brew install qrencode` on macOS)

### Setup

After deploying, SSH into the server and run:

```bash
sudo link-signal.sh
```

This interactive script will:
1. Start the signal-cli linking process
2. Display a QR code in the terminal
3. Wait for you to scan it with Signal (Settings > Linked Devices > Link New Device)
4. Auto-configure `/etc/openclaw-alerts.conf` with your number
5. Send a test alert to confirm everything works

**If the terminal QR code is hard to scan**, the script prints the raw URI. Copy it to your Mac:
```bash
echo 'PASTE_URI_HERE' | qrencode -o /tmp/signal.png && open /tmp/signal.png
```

### Sending a Manual Alert

```bash
sudo /usr/local/bin/send-alert.sh "Your message here"
```

### Troubleshooting

- **No messages received:** Check "Note to Self" in Signal — that's where alerts from your own number appear
- **signal-cli not linked:** `sudo cat /var/lib/signal-cli/.local/share/signal-cli/data/accounts.json`
- **SIGNAL_SENDER not set:** `sudo cat /etc/openclaw-alerts.conf` — must have your number
- **Re-link:** `sudo rm -rf /var/lib/signal-cli/.local/share/signal-cli/data/ && sudo link-signal.sh`
- **First send slow (~10-30s):** Normal — signal-cli syncs contacts on first use after restart
- **CDSI refresh warning in logs:** Harmless — the JVM version logs a warning but sends successfully
- **Revoke access:** Open Signal on your phone > Settings > Linked Devices > remove the server's device

## Outbound Proxy

All outbound HTTP/HTTPS traffic is filtered through a Squid forward proxy with an allowlist. Only explicitly permitted domains can be accessed — everything else is blocked.

### Why

Most server hardening focuses on inbound traffic. But a compromised process can still exfiltrate data or download payloads via outbound connections. The allowlist approach ensures only explicitly permitted domains can be reached.

### How It Works

```
┌──────────────┐     ┌──────────────┐     ┌──────────┐
│ Application  │────►│ Squid proxy  │────►│ Allowed  │
│ (port 3128)  │     │ (localhost)  │     │ domains  │
└──────────────┘     └──────────────┘     └──────────┘
                           │
                     ┌─────▼─────┐
                     │  DENIED   │
                     │ (403/REJ) │
                     └───────────┘
```

1. **Squid** listens on `127.0.0.1:3128` as a forward proxy
2. **CONNECT ACL** filters HTTPS by hostname (no SSL interception/MITM, no cert pinning issues)
3. **Allowlist** at `/etc/squid/allowed-domains.txt` — only these domains are permitted
4. **iptables enforcement** — non-root, non-proxy users are blocked from direct HTTP/HTTPS via `ufw-before-output` chain rules
5. **APT and system-wide proxy** env vars route all package managers and CLI tools through squid

### Allowed Domains

The default allowlist covers essential services only:

| Category | Domains |
|---|---|
| **Ubuntu packages** | `.ubuntu.com`, `.canonical.com`, `.launchpad.net` |
| **Tailscale** | `.tailscale.com`, `.tailscale.io` |
| **Signal** | `.signal.org`, `.whispersystems.org` |
| **GitHub** | `.github.com`, `.githubusercontent.com` |
| **Scaleway** | `.scw.cloud`, `.scaleway.com` |
| **Node.js** | `.nodesource.com`, `.npmjs.org`, `.npmjs.com` |
| **AI APIs** | `.anthropic.com`, `.openai.com`, `.openrouter.ai`, `.brave.com` |
| **Telegram** | `.telegram.org` |
| **Extra** | User-defined via `TF_VAR_squid_extra_domains` (sensitive) |

### Managing the Allowlist

```bash
# View current allowlist
cat /etc/squid/allowed-domains.txt

# Add a domain (prefix with . for all subdomains)
echo ".example.com" | sudo tee -a /etc/squid/allowed-domains.txt

# Reload squid (no restart needed)
sudo systemctl reload squid

# Test
curl -x http://127.0.0.1:3128 https://example.com    # should work
curl -x http://127.0.0.1:3128 https://facebook.com    # should get 403
```

### iptables Enforcement

Direct HTTP/HTTPS bypassing the proxy is blocked at the kernel level via owner-based iptables rules in the UFW `ufw-before-output` chain:

- **proxy** (squid) user: allowed direct HTTP/HTTPS (squid's own outbound connections)
- **root**: allowed direct HTTP/HTTPS (needed for Tailscale, systemd services)
- **signal** user: allowed direct HTTPS only (signal-cli needs direct access to Signal servers)
- **openclaw** user: must go through squid (AI API, Telegram, and tool domains controlled via allowlist)
- **Everyone else**: must go through squid on port 3128, direct 80/443 is REJECTED
- Rules are written to `/etc/ufw/before.rules` and loaded via `ufw reload` — persist across reboots

**Scope:** The proxy enforces filtering for all non-system users, including openclaw. Only root, proxy (squid), and signal have direct outbound access as required by their services. Openclaw's outbound traffic is fully controlled by the squid allowlist. DNS queries are not filtered by squid (they use UDP, not HTTP).

### Blocked Request Alerts

When squid blocks an outbound request, you get a Signal alert. A cron job runs every 5 minutes, checks for new `TCP_DENIED` entries in the squid access log, and sends a batched summary:

```
Squid blocked 7 outbound request(s) on openclaw-prod:
  3 facebook.com
  2 twitter.com
  2 tiktok.com
```

- Alerts are batched — one message per 5-minute window, not per request
- Duplicate domains are counted and deduplicated
- Top 10 blocked domains are included per alert
- No alert is sent if nothing was blocked
- State is tracked via `/var/run/squid-denied-alert.offset` and survives log rotation

### Troubleshooting

```bash
# Check squid status
sudo systemctl status squid

# View recent access log (allowed and denied requests)
sudo tail -50 /var/log/squid/access.log

# Check iptables enforcement rules
sudo iptables -L ufw-before-output -n -v | grep -E "80|443"

# Test proxy directly
curl -v -x http://127.0.0.1:3128 https://github.com

# If a service needs a new domain, check what's being blocked
sudo tail -f /var/log/squid/access.log | grep DENIED

# Manually trigger the blocked request alert (doesn't wait for cron)
sudo /usr/local/bin/squid-denied-alert.sh
```

## Security Details

### Metadata API Blocking

Scaleway instances expose cloud-init user_data (containing secrets like Tailscale auth keys and S3 credentials) via `http://169.254.42.42/conf`. This is blocked via iptables and persisted in UFW `before.rules` so it survives reboots.

**Timing:** The block is applied at the end of cloud-init's `runcmd`, after all services are configured but before the final reboot. After reboot, the block loads from `before.rules` early in the boot process.

```bash
# Verify the block is active
curl -s --max-time 2 http://169.254.42.42/conf && echo "EXPOSED" || echo "Blocked (good)"
```

### AIDE File Integrity

AIDE monitors system files for unauthorized changes. The baseline is initialized at the end of cloud-init (after all services are configured).

```bash
# View what AIDE monitors
sudo aide --config-check

# Run a manual check
sudo aide --check

# Update baseline after intentional changes (e.g., config edits)
sudo aideinit && sudo cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db

# Exclude noisy directories (edit and re-init)
sudo vim /etc/aide/aide.conf
```

To add custom paths to monitoring, edit `/etc/aide/aide.conf` and re-initialize the baseline.

### Auditd

Custom audit rules track security-relevant events:

| Rule | What it tracks |
|---|---|
| `sudo_usage` | All sudo invocations by non-root users |
| `su_usage` | All su invocations |
| `passwd_changes` | Changes to `/etc/passwd`, `/etc/shadow`, `/etc/group` |
| `sshd_config` | SSH configuration changes |
| `ufw_changes` | Firewall rule changes |
| `cron_changes` | Cron job modifications |

Rules are set to immutable (`-e 2`) — auditing cannot be disabled without a reboot.

```bash
# View all active audit rules
sudo auditctl -l

# Search for specific events
sudo ausearch -k sudo_usage --start today

# Full audit log
sudo journalctl -u auditd --no-pager -n 100
```

### Backup Restore

If you need to restore from backup:

```bash
# List available snapshots
sudo bash -c 'source /root/.restic-env && restic snapshots'

# Restore a specific snapshot to a temp directory
sudo bash -c 'source /root/.restic-env && restic restore latest --target /tmp/restore'

# Restore specific files
sudo bash -c 'source /root/.restic-env && restic restore latest --target / --include /etc/ssh/'
```

**If the backup password is lost**, the backups are unrecoverable. The password exists only in `/root/.restic-env` on the server.

### Cron Job Failure Handling

All cron jobs log to syslog. If a job fails:

- **backup-server.sh**: Logs errors to `restic-backup` syslog tag. If signal-cli is linked, sends a failure alert.
- **aide-check.sh**: Only alerts if changes are detected — silence means no changes (healthy).
- **squid-denied-alert.sh**: Only alerts if blocked requests exist — silence means nothing was blocked.

```bash
# Check backup logs
sudo journalctl -t restic-backup --no-pager -n 20

# Check all cron execution
sudo grep CRON /var/log/syslog | tail -20

# Check signal-cli alert delivery
sudo journalctl -t signal-alert --no-pager -n 20
```

## Automated Jobs

| Schedule | Job | Details |
|---|---|---|
| Every 5 min | `squid-denied-alert.sh` | Signal alert for blocked outbound requests |
| Nightly 2am | `backup-server.sh` | Restic backup of system configs to S3 |
| Nightly 3am | `aide-check.sh` | File integrity check, alerts on changes |
| Nightly 3am | `unattended-upgrades` | Security patches, auto-reboot if needed |

## Openclaw Details

Openclaw is deployed as a systemd service (`openclaw.service`) running as a dedicated `openclaw` user with security hardening (private tmp, protected system, restricted syscalls). The version is pinned via `openclaw_version` (default `v2026.2.14`) for reproducible deploys.

All outbound traffic from openclaw is routed through the squid proxy — it cannot access any domain not on the allowlist. Core API domains (`.anthropic.com`, `.openai.com`, `.openrouter.ai`, `.telegram.org`, `.brave.com`) are in the base allowlist; additional domains are added via `TF_VAR_squid_extra_domains` (sensitive).

### Optimised Config

When `openclaw_optimised_config = true` (default), a multi-model config is deployed on first boot:

| Role | Model | Cost |
|---|---|---|
| **Primary** | `openrouter/deepseek/deepseek-v3.2` | Paid (via OpenRouter) |
| **Fallback** | `anthropic/claude-sonnet-4-5` | Paid |
| **Subagents** | `openrouter/google/gemini-2.5-flash-lite` (max 1 concurrent) | ~$0 |
| **Heartbeat** | `openrouter/google/gemini-2.5-flash-lite` (every 120m) | ~$0 |

Requires `TF_VAR_openrouter_key` in `.env.terraform` for OpenRouter models (primary, subagents, heartbeat). Set `openclaw_optimised_config = false` for vanilla defaults.

Access the web UI via SSH tunnel:
```bash
ssh -L 18789:127.0.0.1:18789 <admin_username>@<tailscale-hostname>
open http://localhost:18789
```

## File Structure

```
terraform/
├── bootstrap/
│   └── init-remote-state.sh    # Run first — creates S3 buckets
├── backend-config.tf           # Auto-generated by bootstrap (gitignored)
├── providers.tf                # Scaleway provider config
├── variables.tf                # Input variable definitions
├── terraform.tfvars.example    # Template — copy to terraform.tfvars
├── main.tf                     # Instance + security group
├── storage.tf                  # IAM for backup credentials
├── outputs.tf                  # IP, SSH command, next steps
├── cloud-init.yaml             # Server provisioning template
├── .env.terraform              # Scaleway credentials (gitignored)
├── terraform.tfvars            # Your config (gitignored)
└── .gitignore
```

## Managing Infrastructure

```bash
# Preview changes
source .env.terraform && terraform plan

# Apply changes
terraform apply

# View current state
terraform output

# Scale instance (edit terraform.tfvars, change instance_type)
terraform apply

# Destroy everything (deletes the server!)
source .env.terraform && terraform destroy
```

## Useful Commands

Two ways to SSH in:
- `tailscale ssh <admin>@<hostname>` — Tailscale SSH (no keys needed, authenticates via Tailscale identity)
- `ssh <admin>@<hostname>.tail0010be.ts.net` — standard SSH over Tailscale network (uses SSH keys, supports `-L` port forwarding for the web UI tunnel)

### Tailscale

```bash
# Check Tailscale status
tailscale status

# See all devices on your tailnet
tailscale status --peers

# Check Tailscale IP
tailscale ip -4
```

### Openclaw

```bash
# Service status
sudo systemctl status openclaw

# Restart openclaw (picks up .env and config changes)
sudo systemctl restart openclaw

# Stop / start
sudo systemctl stop openclaw
sudo systemctl start openclaw

# Check gateway is listening
sudo ss -tlnp | grep 18789

# View app output log
sudo tail -30 /var/log/openclaw/output.log

# View app error log
sudo tail -30 /var/log/openclaw/error.log

# View config
sudo cat /var/lib/openclaw/openclaw.json

# View environment variables
sudo cat /var/lib/openclaw/.env

# Check version
sudo -u openclaw node /opt/openclaw/openclaw.mjs --version

# Run doctor (validates config)
sudo -u openclaw OPENCLAW_STATE_DIR=/var/lib/openclaw node /opt/openclaw/openclaw.mjs doctor

# Fix invalid config keys
sudo -u openclaw OPENCLAW_STATE_DIR=/var/lib/openclaw node /opt/openclaw/openclaw.mjs doctor --fix

# View heartbeat file
sudo cat /var/lib/openclaw/.openclaw/workspace/HEARTBEAT.md

# Kill stale gateway processes (if port 18789 is stuck)
sudo pkill -f openclaw-gateway && sudo systemctl start openclaw
```

### Squid Proxy

```bash
# View allowed domains
cat /etc/squid/allowed-domains.txt

# Add a domain (prefix with . for all subdomains)
echo ".example.com" | sudo tee -a /etc/squid/allowed-domains.txt
sudo systemctl reload squid

# View recent proxy traffic
sudo tail -30 /var/log/squid/access.log

# Check for blocked (denied) requests
sudo grep 'TCP_DENIED' /var/log/squid/access.log | tail -20

# Check Anthropic API calls (useful for monitoring heartbeat cost)
sudo grep 'anthropic' /var/log/squid/access.log | tail -10

# Count API calls by domain today
sudo awk '{print $7}' /var/log/squid/access.log | sort | uniq -c | sort -rn | head -10

# Reload config after allowlist changes
sudo systemctl reload squid
```

### System

```bash
# Cloud-init status (was provisioning successful?)
sudo cloud-init status

# Cloud-init output log (full provisioning log)
sudo tail -50 /var/log/cloud-init-output.log

# Memory and load
free -h && uptime

# Disk usage
df -h /

# Check running services
sudo systemctl list-units --type=service --state=running

# Check firewall rules
sudo ufw status verbose

# Check iptables outbound rules
sudo iptables -L OUTPUT -n --line-numbers

# View recent security alerts
sudo journalctl -t signal-alert --no-pager -n 20

# Check backups
sudo journalctl -t restic-backup --no-pager -n 20
```

## Troubleshooting

**Can't SSH after apply:**
Server is still running cloud-init or rebooting. Wait 5-10 minutes.

**Cloud-init failed:**
```bash
sudo cat /var/log/cloud-init-output.log
```

**Tailscale not connecting:**
```bash
sudo tailscale up --ssh --accept-routes
```

**Terraform says "bucket not found":**
Run the bootstrap script first: `cd bootstrap && ./init-remote-state.sh`

**signal-cli not working:**
See [Signal Alerts > Troubleshooting](#troubleshooting-2) for detailed steps.

**Backup failed:**
```bash
sudo journalctl -t restic-backup --no-pager -n 50
sudo bash -c 'source /root/.restic-env && restic snapshots'
```

## Contributing

See [contributing guidelines](../README.md#contributing) in the root README.
