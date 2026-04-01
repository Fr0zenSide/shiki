# Radar: Vaultwarden for Self-Hosted Secret Management

**Date:** 2026-04-01
**Source:** https://github.com/dani-garcia/vaultwarden
**Version analyzed:** 1.35.4 (2026-02-23)
**Status:** ADOPT (strong recommendation for Shikki infrastructure)

---

## 1. What Is It

Vaultwarden is an unofficial, Bitwarden-compatible server written in Rust. It implements the full Bitwarden Client API, meaning all official Bitwarden clients (desktop, mobile, browser, CLI) work against it without modification. Originally named `bitwarden_rs`, it was renamed in 2021 to avoid trademark confusion.

Key facts:
- **Language:** Rust (Rocket web framework)
- **License:** AGPL-3.0-only (same license as Shikki -- full compatibility)
- **Stars:** 57,708 (as of 2026-04-01)
- **Forks:** 2,671
- **Open issues:** 13 (extremely low for a project this size)
- **Created:** 2018-02-17 (8 years of maturity)
- **Latest release:** 1.35.4 (2026-02-23), active development with monthly releases
- **One maintainer is employed by Bitwarden** (contributes independently, reviewed by other maintainers)

Resource footprint is tiny compared to the official Bitwarden server (which requires MSSQL + .NET):
- Runs on ~50-80MB RAM with SQLite backend
- Single static binary + web vault (Alpine container ~100MB)
- SQLite, MySQL, or PostgreSQL backends supported

---

## 2. How It Stores Secrets (Encryption Model)

Vaultwarden follows the Bitwarden encryption architecture -- it is a **zero-knowledge** system:

### Client-Side Encryption
- All vault data (passwords, notes, card numbers, SSH keys, custom fields) is encrypted **on the client** before transmission
- The server **never** sees plaintext secrets
- Master password is never transmitted -- only a derived key hash

### Key Derivation
- PBKDF2-HMAC-SHA256 (default 600,000 iterations, configurable per user)
- Argon2id also supported (recommended for new setups)
- Master password -> Master Key -> Symmetric Key (AES-256-CBC + HMAC-SHA256)
- Each item encrypted with organization key or personal symmetric key

### Server-Side Storage
- Encrypted blobs stored in the database (SQLite/PostgreSQL/MySQL)
- RSA-2048 keypair generated at first run for JWT signing and key exchange
- Server stores: encrypted ciphers, encrypted organization keys, user metadata, device info
- Attachments encrypted client-side before upload, stored in `DATA_FOLDER/attachments/`

### At-Rest Security
- Database contains only encrypted payloads -- even a full DB dump reveals nothing without the master password
- No server-side decryption capability whatsoever
- Admin panel can manage users/orgs but cannot read vault contents

---

## 3. CLI Access (Bitwarden CLI Compatibility)

Vaultwarden is fully compatible with the official Bitwarden CLI (`bw`). This is the primary interface for programmatic secret retrieval.

### Setup
```bash
# Install Bitwarden CLI
brew install bitwarden-cli  # macOS
npm install -g @bitwarden/cli  # cross-platform

# Point to self-hosted Vaultwarden
bw config server https://vw.obyw.one

# Login
bw login user@example.com

# Unlock (session-based, returns session key)
export BW_SESSION=$(bw unlock --raw)
```

### Programmatic Secret Retrieval
```bash
# Get a specific password by name
bw get password "VPS Production SSH"

# Get full item as JSON
bw get item "NATS Auth Token" | jq '.login.password'

# Get custom field
bw get item "VPS Config" | jq '.fields[] | select(.name=="IP") | .value'

# List all items in a folder
bw list items --folderid $(bw get folder "Infrastructure" | jq -r '.id')

# Get TOTP code
bw get totp "GitHub"

# Get notes (for multi-line configs, SSH keys)
bw get notes "Production SSH Key"

# Search
bw list items --search "VPS"
```

### API Key Authentication (Non-Interactive)
For CI/CD and agents, Bitwarden supports API key auth (no interactive password prompt):
```bash
# Set env vars for non-interactive auth
export BW_CLIENTID="user.xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export BW_CLIENTSECRET="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
export BW_PASSWORD="master-password"

# Login with API key
bw login --apikey

# Unlock
export BW_SESSION=$(bw unlock --raw)

# Now use normally
bw get password "some-secret"
```

The Personal API Key is generated from the web vault under Account Settings > Security > Keys.

---

## 4. Agent / Script Programmatic Access

### Bitwarden CLI in Scripts
The `bw` CLI is the recommended path. Pattern for agents:

```bash
#!/bin/bash
# Agent bootstrap: unlock vault, export session
export BW_SESSION=$(bw unlock --raw <<< "$BW_PASSWORD")

# Retrieve secrets
NATS_TOKEN=$(bw get password "NATS Auth Token")
VPS_IP=$(bw get item "VPS Production" | jq -r '.fields[] | select(.name=="IP") | .value')
SSH_KEY=$(bw get notes "Production SSH Key")
```

### Bitwarden REST API (Direct HTTP)
Vaultwarden exposes the full Bitwarden API. Agents can authenticate via OAuth2:

```bash
# 1. Get access token (OAuth2 password grant)
curl -X POST https://vw.obyw.one/identity/connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=user.xxx" \
  -d "client_secret=xxx" \
  -d "scope=api" \
  -d "deviceType=8" \
  -d "deviceIdentifier=shikki-agent-$(hostname)" \
  -d "deviceName=ShikkiAgent"

# 2. Use access_token for API calls
curl -H "Authorization: Bearer $ACCESS_TOKEN" \
  https://vw.obyw.one/api/ciphers

# Note: responses are encrypted -- you need the client SDK to decrypt
```

### Bitwarden SDK (Native Libraries)
Bitwarden provides an official SDK (`bitwarden/sdk`) with bindings for:
- Rust (native)
- Python, Node.js, Ruby, Go, Java, C#

This is the cleanest path for programmatic access from ShikiCore (Swift can call Rust via C FFI or use the CLI).

### Bitwarden Secrets Manager
Bitwarden also offers "Secrets Manager" (separate product for machine-to-machine secrets). Vaultwarden does **not** implement Secrets Manager APIs. For Shikki, the standard vault + CLI is sufficient since we control both ends.

---

## 5. iOS / macOS Integration

### Bitwarden App (Official)
- iOS and macOS Bitwarden apps work directly with Vaultwarden
- Configure custom server URL in the app (Settings > Self-hosted > Server URL)
- Full autofill integration on iOS (Settings > Passwords > AutoFill Passwords)
- Safari extension on macOS
- Push notifications require Bitwarden's push relay (free registration at bitwarden.com/host)

### Apple Keychain Relationship
- Vaultwarden does **not** integrate with Apple Keychain directly
- They are parallel systems: Keychain for OS-level secrets, Vaultwarden for cross-platform secrets
- SecurityKit (Shikki's existing Keychain wrapper) remains the right choice for on-device secrets
- Vaultwarden is the right choice for secrets that need to be shared across Mac + Linux VPS + iOS + CI/CD

### Recommended Split
| Secret Type | Storage |
|---|---|
| App signing certs, local dev tokens | Apple Keychain (SecurityKit) |
| SSH keys, API tokens, VPS configs | Vaultwarden |
| NATS auth, CI/CD secrets | Vaultwarden |
| User-facing passwords (personal) | Vaultwarden (already using Bitwarden?) |

---

## 6. Linux Support

Excellent. Vaultwarden is Linux-first:
- Official Docker images: Alpine and Debian variants
- Architectures: amd64, arm64, armv7, armv6
- Native binary can be compiled from source (Rust toolchain)
- Systemd service files available in community packages
- Third-party packages: Arch (AUR), NixOS, FreeBSD, Debian/Ubuntu unofficial repos

For the VPS (92.134.242.73), deployment options:
```bash
# Option A: Docker (simplest)
docker run -d --name vaultwarden \
  -e DOMAIN=https://vw.obyw.one \
  -v /opt/vaultwarden/data:/data \
  -p 127.0.0.1:8000:80 \
  --restart unless-stopped \
  vaultwarden/server:latest

# Option B: Native binary (matches Shikki prod philosophy -- no Docker in prod)
# Build from source, run as systemd service behind Caddy
# Caddy already runs on the VPS for other services
```

Given Shikki's "native binaries only in prod" rule, Option B is preferred:
```ini
# /etc/systemd/system/vaultwarden.service
[Unit]
Description=Vaultwarden
After=network.target

[Service]
User=vaultwarden
Group=vaultwarden
ExecStart=/opt/vaultwarden/vaultwarden
WorkingDirectory=/opt/vaultwarden
EnvironmentFile=/opt/vaultwarden/.env
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Caddy reverse proxy:
```
vw.obyw.one {
    reverse_proxy localhost:8000
}
```

---

## 7. Comparison Matrix

| Criterion | Vaultwarden | Apple Keychain | 1Password CLI | HashiCorp Vault | pass (GPG) |
|---|---|---|---|---|---|
| **Self-hosted** | Yes (own VPS) | No (Apple infra) | No (1Password infra) | Yes | Yes (git repo) |
| **Cross-platform** | Mac + Linux + iOS + Web | Apple only | Mac + Linux + iOS | All | All (CLI) |
| **Zero-knowledge** | Yes | Yes (iCloud) | Yes | No (server decrypts) | Yes |
| **CLI access** | `bw` CLI (excellent) | `security` (macOS only) | `op` CLI | `vault` CLI | `pass` CLI |
| **Agent/CI access** | API key + CLI + SDK | No | Service accounts | AppRole / tokens | GPG + git |
| **iOS app** | Bitwarden app | Native | 1Password app | No | No |
| **Browser extension** | Bitwarden ext | Safari only | 1Password ext | No | browserpass |
| **License** | AGPL-3.0 | Proprietary | Proprietary | BSL 1.1 | GPL-2.0 |
| **Cost** | Free | Free (with Apple) | $3-8/mo | Free (OSS) / paid | Free |
| **Resource usage** | ~50MB RAM | N/A | N/A | ~200MB+ RAM | Negligible |
| **Secret types** | Passwords, notes, cards, SSH keys, custom fields | Passwords, certs, keys | Same as VW | KV, PKI, transit, DB creds | Text files |
| **Dynamic secrets** | No | No | No | Yes (DB creds, PKI) | No |
| **Audit log** | Yes (org events) | No | Yes | Yes (extensive) | git log |
| **2FA** | TOTP, WebAuthn, YubiKey, Duo, Email | Biometric | Biometric, WebAuthn | MFA | No |
| **SSO/OIDC** | Yes (built-in) | No | Yes | Yes | No |
| **Backup** | SQLite file copy | iCloud | 1Password cloud | Raft/Consul | git push |
| **Maturity** | 8 years, 57k stars | Decades | ~10 years | ~12 years | ~12 years |

### Verdict by Use Case

**For Shikki's needs specifically:**
- **HashiCorp Vault** is overkill -- designed for dynamic secrets, service mesh, PKI. We don't need that complexity. BSL license is also a concern.
- **1Password CLI** is excellent but proprietary + paid. Vendor lock-in contradicts Shikki's AI-provider-agnostic philosophy.
- **Apple Keychain** only works on Apple platforms. Useless for the Linux VPS.
- **pass (GPG)** is elegant but has no mobile app, no browser extension, no web UI, no 2FA.
- **Vaultwarden** hits every requirement: self-hosted, cross-platform, CLI-accessible, agent-friendly, iOS-compatible, AGPL-licensed, battle-tested.

---

## 8. Shikki Integration: Replacing PUSH_MAC/PUSH_VPS with Vault Lookups

### Current State (env vars)
```bash
# Current: hardcoded in .envrc or shell profiles
export PUSH_MAC="192.168.1.42"
export PUSH_VPS="92.134.242.73"
```

### Proposed: Vault-Backed Target Resolution
```bash
# Store targets in Vaultwarden as items with custom fields:
# Item: "push-target-mac"  -> fields: { host: "192.168.1.42", user: "jeoffrey", port: "22" }
# Item: "push-target-vps"  -> fields: { host: "92.134.242.73", user: "deploy", port: "22" }

# shiki push integration:
push file.png mac
# Internally resolves to:
#   1. bw get item "push-target-mac" | jq -r '.fields[] | select(.name=="host") | .value'
#   2. scp file.png jeoffrey@192.168.1.42:~/incoming/

# Or with a wrapper function:
vw-target() {
    local target="push-target-$1"
    bw get item "$target" 2>/dev/null | jq -r '.fields[] | select(.name=="'$2'") | .value'
}

push() {
    local file="$1" target="$2"
    local host=$(vw-target "$target" host)
    local user=$(vw-target "$target" user)
    local port=$(vw-target "$target" port)
    scp -P "$port" "$file" "${user}@${host}:~/incoming/"
}
```

### Benefits
- No secrets in env files or shell profiles
- Adding a new target = adding a vault item (no code change)
- Targets queryable from any machine with vault access
- SSH keys also stored in vault, pulled on demand
- Agent can discover targets dynamically: `bw list items --search "push-target-"`

### Implementation Path
1. Deploy Vaultwarden on VPS behind Caddy
2. Create vault items for all infrastructure targets
3. Modify `shiki push` to resolve targets via `bw get`
4. Cache resolved targets locally (5min TTL) to avoid CLI overhead on every call
5. Fallback: if vault unreachable, use cached or env vars

---

## 9. Full Shikki Secret Architecture (Proposed)

```
+------------------+     +-------------------+     +------------------+
|   Apple Keychain |     |    Vaultwarden    |     |   Shiki DB       |
|   (SecurityKit)  |     |   (vw.obyw.one)  |     |   (PocketBase)   |
+------------------+     +-------------------+     +------------------+
| App signing      |     | SSH keys          |     | Agent events     |
| Local dev tokens |     | API tokens        |     | Feature specs    |
| Biometric auth   |     | VPS configs       |     | Decision logs    |
| Session keys     |     | NATS auth         |     | Memory/context   |
|                  |     | Push targets      |     |                  |
|                  |     | CI/CD secrets     |     |                  |
|                  |     | DNS credentials   |     |                  |
+------------------+     +-------------------+     +------------------+
     Apple-only            Cross-platform             App data
     On-device             Self-hosted                Self-hosted
                           Zero-knowledge
```

### Access Patterns
| Consumer | Method | Auth |
|---|---|---|
| Developer (Jeoffrey) | Bitwarden app + browser ext | Master password + 2FA |
| `shiki push` CLI | `bw` CLI | API key + session cache |
| ShikiCore agents | `bw` CLI (shell-out) | API key + session |
| CI/CD (future) | `bw` CLI in pipeline | API key env var |
| iOS apps (WabiSabi/Maya) | SecurityKit (Keychain) | Biometric |

---

## 10. Deployment Plan for VPS

### Prerequisites
- Caddy already running on VPS
- Domain: `vw.obyw.one` (add DNS A record -> 92.134.242.73)

### Steps
```bash
# 1. On VPS: Build from source (native binary, no Docker)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
git clone https://github.com/dani-garcia/vaultwarden.git
cd vaultwarden
cargo build --features sqlite --release
# Binary at target/release/vaultwarden

# 2. Download web vault
VW_VERSION="v2026.2.0"
wget https://github.com/dani-garcia/bw_web_builds/releases/download/$VW_VERSION/bw_web_$VW_VERSION.tar.gz
tar xzf bw_web_$VW_VERSION.tar.gz -C /opt/vaultwarden/

# 3. Configure
cat > /opt/vaultwarden/.env << 'EOF'
DOMAIN=https://vw.obyw.one
DATABASE_URL=/opt/vaultwarden/data/db.sqlite3
DATA_FOLDER=/opt/vaultwarden/data
WEB_VAULT_FOLDER=/opt/vaultwarden/web-vault/
SIGNUPS_ALLOWED=false
INVITATIONS_ALLOWED=false
ADMIN_TOKEN='<argon2id hash>'
SHOW_PASSWORD_HINT=false
LOG_LEVEL=warn
IP_HEADER=X-Forwarded-For
EOF

# 4. Systemd service (as described in section 6)

# 5. Caddy config
# vw.obyw.one {
#     reverse_proxy localhost:8000
# }

# 6. Backup: daily sqlite backup to private git repo
# 0 3 * * * sqlite3 /opt/vaultwarden/data/db.sqlite3 ".backup '/opt/backups/vaultwarden/db-$(date +%Y%m%d).sqlite3'"
```

### Security Hardening
- `SIGNUPS_ALLOWED=false` (only admin can invite)
- `ADMIN_TOKEN` set with Argon2id hash
- Caddy handles TLS automatically (Let's Encrypt)
- `IP_HEADER=X-Forwarded-For` for rate limiting behind proxy
- Enable 2FA immediately after first login (WebAuthn preferred)
- Regular SQLite backups (encrypted at rest by design)

---

## 11. Risks and Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Single point of failure (VPS down = no secrets) | Medium | `bw` CLI caches vault locally (encrypted). Agents use cached sessions. |
| Master password compromise | High | 2FA (WebAuthn/YubiKey). Strong master password. |
| `bw` CLI session key in env var | Medium | Short-lived sessions. Agent clears `BW_SESSION` after use. |
| Vaultwarden security vulnerability | Low | Active maintenance, 13 open issues, quick CVE response (see 1.35.4 notes). |
| Rust build on VPS takes time/resources | Low | Build locally, scp binary. Or use Docker for initial deploy, migrate to native later. |
| CLI overhead per secret lookup | Low | Cache resolved values with TTL. Batch lookups at agent start. |

---

## 12. Action Items for Shikki

| Priority | Action | Effort |
|---|---|---|
| **P1** | Deploy Vaultwarden on VPS (native binary + Caddy) | 2-3 hours |
| **P1** | Migrate SSH keys, API tokens, VPS configs to vault | 1 hour |
| **P1** | Install `bw` CLI on Mac + VPS, configure API key auth | 30 min |
| **P2** | Modify `shiki push` to resolve targets from vault | 1-2 hours |
| **P2** | Add vault lookup helper to ShikiCore agent bootstrap | 1 hour |
| **P3** | Set up daily SQLite backup to private repo | 30 min |
| **P3** | Document secret naming conventions for team | 30 min |

**Total estimated effort:** ~8 hours for full integration.

---

## 13. Naming Convention Proposal

```
# Infrastructure targets
push-target-mac          # Push target: MacBook
push-target-vps          # Push target: VPS
push-target-ipad         # Push target: iPad

# Service credentials
svc-nats-auth            # NATS authentication token
svc-shikidb-admin        # ShikiDB admin credentials
svc-pocketbase-admin     # PocketBase admin
svc-caddy-api            # Caddy API token
svc-github-pat           # GitHub Personal Access Token
svc-ntfy-topic           # ntfy topic + auth

# SSH keys (stored as Secure Notes)
ssh-key-vps-deploy       # VPS deployment key
ssh-key-github           # GitHub SSH key

# DNS / Domain
dns-obyw-one             # Domain registrar credentials
dns-cloudflare-api       # Cloudflare API token (if used)

# AI / API keys
ai-anthropic-api         # Anthropic API key
ai-lmstudio-config       # LM Studio config
```

All items organized into folders: `Infrastructure`, `Services`, `SSH`, `DNS`, `AI`.
