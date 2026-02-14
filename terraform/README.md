# Terraform Configuration

Detailed setup, security documentation, and operational guide. For a quick overview, see the [root README](../README.md).

## What Gets Deployed

| Component | Purpose |
|---|---|
| **Scaleway DEV1-S** | Ubuntu 24.04 LTS instance (2 vCPU, 2GB RAM, 20GB SSD) |
| **Tailscale** | Zero-trust VPN with SSH access |
| **UFW** | Firewall — rate-limited SSH (22/tcp) and Tailscale (41641/udp) only |
| **fail2ban** | Brute-force SSH protection |
| **signal-cli** | Standalone Signal messenger for server alerts |
| **restic** | Encrypted nightly backups to Scaleway S3 |
| **AIDE** | File integrity monitoring (nightly scan) |
| **auditd** | System call auditing |
| **unattended-upgrades** | Automatic security patches with auto-reboot at 3am |
| **prometheus-node-exporter** | System metrics |

### Security Measures

**Network**
- UFW firewall — default deny inbound, only SSH (22/tcp rate-limited) and Tailscale (41641/udp) allowed
- SSH rate-limited at firewall level (6 connections / 30 seconds) before fail2ban even sees it
- fail2ban for brute-force SSH ban
- Tailscale zero-trust VPN — public SSH can be removed once Tailscale is connected
- Scaleway security group — drop all inbound except SSH, Tailscale, ICMP

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
- AIDE file integrity monitoring — nightly scan, alerts on changes
- auditd system call auditing
- prometheus-node-exporter for system metrics

**Updates**
- Unattended security upgrades enabled
- Automatic reboot at 3am if kernel update requires it

**Secrets**
- No secrets in committed files — `terraform.tfvars` and `.env.terraform` are gitignored
- Sensitive variables (`tailscale_auth_key`, `signal_alert_number`) prompted at plan/apply, never written to disk
- Scaleway metadata API (`169.254.42.42`) blocked after provisioning via iptables — prevents any process from reading cloud-init secrets
- Metadata API block persisted across reboots via UFW `before.rules`
- Terraform state stored remotely in a private, versioned S3 bucket — contains secrets, access controlled via Scaleway IAM
- Restic backup password generated once on first boot — must be saved externally

**Backups**
- Nightly encrypted backups of system configs to Scaleway S3 via restic
- Retention: 7 daily, 4 weekly, 12 monthly snapshots
- Repository integrity checked after each backup
- Dedicated IAM credentials scoped to backup bucket only

### Openclaw App

The openclaw application install is **commented out** in `cloud-init.yaml`. This lets you verify the base infrastructure works before adding the app. See [Enabling Openclaw](#enabling-openclaw) below.

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

The following sensitive variables are **prompted during plan/apply** (not stored in files):
- `tailscale_auth_key` — from prerequisites
- `signal_alert_number` — your phone number in E.164 format (e.g. `+15551234567`)

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

### 1. SSH In

```bash
ssh -i ~/.ssh/openclaw_ed25519 <admin_username>@<public_ip>
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

Then go to the **Machines** tab, find your server, and apply the `tag:openclaw` tag.

- `check` mode requires browser re-authentication before granting SSH — more secure than `accept`
- `autogroup:nonroot` prevents root SSH, matching the server-side hardening
- The tag scopes SSH access to only your openclaw server

**Test from your local machine** (must have [Tailscale installed](https://tailscale.com/download) and logged in):
```bash
ssh -i ~/.ssh/openclaw_ed25519 <admin_username>@<tailscale_ip>
```

### 6. Link signal-cli

signal-cli is installed but needs to be linked to a Signal account before alerts work. Until linked, alerts fall back to syslog.

```bash
# Link as secondary device to your existing Signal account
sudo signal-cli link -n "openclaw-server"
# Prints a tsdevice:// URI — open in Signal app > Linked Devices

# Set your sender number
sudo sed -i 's/SIGNAL_SENDER=""/SIGNAL_SENDER="+YOUR_NUMBER"/' /etc/openclaw-alerts.conf

# Test
sudo /usr/local/bin/send-alert.sh "Test alert from openclaw server"
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

## Automated Jobs

| Schedule | Job | Details |
|---|---|---|
| Nightly 2am | `backup-server.sh` | Restic backup of system configs to S3 |
| Nightly 3am | `aide-check.sh` | File integrity check, alerts on changes |
| Nightly 3am | `unattended-upgrades` | Security patches, auto-reboot if needed |

## Enabling Openclaw

The openclaw application sections are commented out in `cloud-init.yaml` (search for `OPENCLAW:`). To enable:

1. Uncomment all `OPENCLAW:` sections in `cloud-init.yaml`
2. Add `openclaw_api_key` to the `templatefile()` params in `main.tf`
3. Set `openclaw_api_key` in `terraform.tfvars`
4. Run `terraform apply` (this will recreate the instance)

This installs Node.js, creates an `openclaw` system user, clones the repo, and runs it as a systemd service with security hardening (private tmp, protected system, restricted syscalls).

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
Check Java is installed (`java -version`) and signal-cli is linked (`signal-cli -a "+YOUR_NUMBER" listAccounts`).

**Backup failed:**
```bash
sudo journalctl -t restic-backup --no-pager -n 50
sudo bash -c 'source /root/.restic-env && restic snapshots'
```

## Contributing

See [contributing guidelines](../README.md#contributing) in the root README.
