# Radar: Pangolin & Open-Source Mesh VPN Landscape

**Date**: 2026-04-01
**Use case**: iPad (Blink SSH) -> Mac at home, mosh (UDP), self-hosted on VPS (92.134.242.73), no proprietary cloud dependency

---

## TL;DR — Recommendation

**Headscale + Tailscale clients = best fit for this use case.**

Pangolin is impressive but solves a different problem (identity-aware reverse proxy + VPN hybrid). For the specific need of "iPad mosh to Mac over self-hosted WireGuard mesh", Headscale is the clear winner: zero-config UDP support, official Tailscale iOS app compatibility, battle-tested NAT traversal, and the lightest self-hosted footprint.

---

## 1. Pangolin (fosrl/pangolin)

| Attribute | Value |
|---|---|
| **What** | Identity-aware reverse proxy + VPN platform built on WireGuard |
| **Stars** | 19,764 |
| **License** | Dual: AGPL-3 (Community) + Fossorial Commercial License (Enterprise) |
| **Language** | TypeScript |
| **Created** | 2024-09-27 |
| **Latest release** | 1.17.0-rc.0 (2026-03-31) — very active |
| **Contributors** | ~5 core (oschwartz10612 dominant with 3,027 commits) |

### What it is

Pangolin is **not a mesh VPN**. It is a **self-hosted reverse proxy + VPN hybrid** — closer to a self-hosted Cloudflare Tunnel with added WireGuard VPN capabilities. It has two modes:

1. **Reverse proxy mode** (browser-based): Expose web apps through tunneled proxies with SSO, SSL, identity-aware routing. This is its primary strength — a Cloudflare Tunnel/ngrok replacement.
2. **Private resource mode** (client-based VPN): Access SSH, databases, RDP, and network ranges through WireGuard tunnels via native clients.

### Architecture

- **Pangolin** — Control plane + admin dashboard (TypeScript/Node)
- **Newt** — Lightweight site connector agent (runs on your LAN, tunnels back to Pangolin server)
- **Gerbil** — WireGuard tunnel relay (handles NAT traversal, UDP port 21820)
- **Badger** — Traefik authentication middleware (bouncer)
- **Traefik** — Reverse proxy (handles HTTP routing, SSL)

### iOS/iPad support

YES — native iOS client on the App Store ("Pangolin Client", requires iOS 17+). Creates WireGuard VPN tunnel for private resource access.

### UDP / mosh support

YES (in private resource mode) — the docs explicitly reference "TCP & UDP resources" configuration. Since private resources use WireGuard tunnels, arbitrary UDP traffic (including mosh on ports 60000-61000) should work.

### Self-hosted setup complexity

MODERATE-HIGH:
- Requires Docker (pulls pangolin, gerbil, traefik images)
- Needs domain name + DNS pointing to VPS
- Ports: 80 (TCP), 443 (TCP), 51820 (UDP), 21820 (UDP)
- Automated installer script, ~5 min setup
- More infrastructure than needed for the iPad-to-Mac use case

### Verdict for this use case

**Overkill.** Pangolin shines for exposing multiple web services with SSO and access control — it is a Cloudflare Tunnel killer. For simple "iPad SSH/mosh to Mac", it brings unnecessary complexity (Traefik, reverse proxy, identity management). The VPN mode works but is secondary to its reverse proxy focus.

---

## 2. Headscale (juanfont/headscale) — RECOMMENDED

| Attribute | Value |
|---|---|
| **What** | Self-hosted Tailscale control server |
| **Stars** | 36,993 |
| **License** | BSD-3-Clause |
| **Language** | Go |
| **Created** | 2020-06-21 |
| **Latest release** | v0.28.0 (2026-02-04) |
| **Maturity** | High — 5+ years, active maintainer employed by Tailscale |

### What it is

Headscale is an **open-source reimplementation of the Tailscale control server**. It is API-compatible with official Tailscale clients, meaning you get the full Tailscale experience (mesh VPN, NAT traversal, MagicDNS) but self-hosted on your own infrastructure with zero proprietary cloud dependency.

### How it works

- Headscale runs on your VPS as the coordination server
- Official Tailscale clients (macOS, iOS, Linux, etc.) connect to it instead of Tailscale's cloud
- WireGuard mesh network is established peer-to-peer between all your devices
- DERP relay servers handle fallback when direct P2P fails (you can self-host these too)

### iOS/iPad support

YES — the **official Tailscale iOS app** works with Headscale. The docs confirm iOS, macOS, tvOS all show "Yes" for Headscale compatibility. Blink SSH on iPad can use the Tailscale VPN tunnel.

### UDP / mosh support

YES, natively. Tailscale/Headscale creates a full Layer 3 WireGuard mesh. All TCP and UDP traffic works transparently. mosh just works — connect to the Tailscale IP (100.x.y.z) of your Mac and mosh uses UDP as normal.

### Self-hosted setup complexity

LOW:
- Single Go binary on VPS (no Docker required, though Docker option exists)
- No domain name required (can use IP directly)
- No Traefik, no reverse proxy, no SSL cert management
- Minimal config: listen address, DB path, DERP map
- Clients authenticate via pre-auth keys or OIDC

### Setup steps (estimated 10 minutes)

```bash
# On VPS (92.134.242.73)
wget https://github.com/juanfont/headscale/releases/download/v0.28.0/headscale_0.28.0_linux_amd64.deb
sudo dpkg -i headscale_0.28.0_linux_amd64.deb
# Edit /etc/headscale/config.yaml (set server_url, listen_addr)
sudo systemctl enable --now headscale

# Create user + pre-auth key
headscale users create jeoffrey
headscale preauthkeys create --user jeoffrey --reusable --expiration 24h

# On Mac: install Tailscale, point to Headscale
tailscale up --login-server=http://92.134.242.73:8080 --authkey=YOUR_KEY

# On iPad: Tailscale app -> custom control server -> same URL + key
```

### Features

- MagicDNS (name your devices, e.g., `mac.tailnet`)
- Subnet routers + exit nodes
- ACLs for access control
- Taildrop (file sharing)
- Tailscale SSH
- OIDC SSO (optional)
- Ephemeral nodes

### Limitations vs Tailscale Cloud

- No Funnel/Serve (exposing services to internet — use Pangolin for that)
- OIDC groups cannot be used in ACLs
- No network flow logs
- Single tailnet only (fine for personal use)

### Verdict for this use case

**Perfect fit.** Lightest footprint, uses the battle-tested Tailscale iOS client, full UDP support, zero proprietary dependency, and the simplest setup. mosh will "just work" over the mesh. BSD-3-Clause is the cleanest license. 37k stars and Tailscale-employed maintainer = long-term stability.

---

## 3. NetBird (netbirdio/netbird)

| Attribute | Value |
|---|---|
| **What** | WireGuard-based mesh VPN with SSO and access control |
| **Stars** | 23,983 |
| **License** | Mixed: BSD-3 (client) + AGPL-3 (management/signal/relay) |
| **Language** | Go |
| **Created** | 2021-04-14 |
| **Latest release** | v0.67.1 (2026-03-26) — very active |

### What it is

NetBird is a **peer-to-peer mesh VPN** with a centralized management plane. It is a full alternative to Tailscale (not a Tailscale-compatible implementation like Headscale). It has its own clients, its own control plane, and its own NAT traversal (WebRTC ICE + STUN/TURN).

### iOS/iPad support

YES — native iOS client available.

### UDP / mosh support

YES — full WireGuard mesh, all Layer 3 traffic works.

### Self-hosted setup complexity

MODERATE:
- Docker Compose deployment with multiple services (management, signal, relay, dashboard, coturn)
- Requires domain name, SSL, and an identity provider (Zitadel, Keycloak, Auth0, etc.)
- More moving parts than Headscale
- Good quick-start script, but heavier infrastructure

### Standout features

- Kernel WireGuard support (faster than userspace)
- Quantum-resistance via Rosenpass
- Device posture checks
- Admin web UI (built-in)
- Terraform provider
- Network flow logs

### Verdict for this use case

**Good but heavier than needed.** NetBird is a serious enterprise-grade alternative to Tailscale, but requiring an external identity provider (Zitadel/Keycloak) for self-hosting adds significant setup complexity. For a personal iPad-to-Mac tunnel, this is over-engineered.

---

## 4. Netmaker (gravitl/netmaker)

| Attribute | Value |
|---|---|
| **What** | WireGuard network automation platform |
| **Stars** | 11,515 |
| **License** | Mixed: Apache 2.0 + proprietary "pro/" directory |
| **Language** | Go |
| **Created** | 2021-03-25 |

### What it is

Netmaker automates WireGuard networks — mesh VPNs, site-to-site, remote access gateways. It is more infrastructure-focused (data centers, clouds, edge devices) than personal-use focused.

### iOS/iPad support

LIMITED — primarily Linux/Mac/Windows/Docker. No native iOS app found. Android only via third-party WireGuard config export.

### Self-hosted setup complexity

MODERATE — Docker Compose, needs domain + DNS, ports 443 + 51821.

### Verdict for this use case

**Not a fit.** No iOS client is a dealbreaker. Netmaker targets infrastructure teams, not personal device connectivity.

---

## 5. ZeroTier (zerotier/ZeroTierOne)

| Attribute | Value |
|---|---|
| **What** | Software-defined Ethernet switch (Layer 2 overlay) |
| **Stars** | 16,590 |
| **License** | Mixed: MPL-2.0 (core) + proprietary (controller) |
| **Language** | C++ |
| **Created** | 2013-04-24 |

### What it is

ZeroTier creates a virtual Ethernet network (Layer 2) between devices. Unlike WireGuard-based solutions that work at Layer 3, ZeroTier emulates a switch, making devices appear on the same LAN.

### iOS/iPad support

YES — iOS/Android apps available.

### UDP / mosh support

YES — full Layer 2, so everything works.

### Self-hosted controller

PARTIAL — the network controller code is "source available" (nonfree/ directory) but not truly open source. You can self-host `ztncui` or use the free tier of ZeroTier Central (cloud), but the controller is not AGPL/BSD/MIT.

### Verdict for this use case

**Viable but not fully open source.** The controller is proprietary/"source available". ZeroTier Central's free tier (25 devices) works fine for personal use, but violates the "no proprietary cloud dependency" requirement. Self-hosting the controller is possible but poorly documented and not a first-class experience.

---

## Comparison Matrix

| Feature | Headscale | Pangolin | NetBird | Netmaker | ZeroTier |
|---|---|---|---|---|---|
| **Stars** | 37k | 20k | 24k | 12k | 17k |
| **License** | BSD-3 | AGPL-3/FCL | BSD-3/AGPL-3 | Apache/prop | MPL/prop |
| **Type** | Mesh VPN (WG) | Reverse proxy + VPN | Mesh VPN (WG) | WG automation | L2 overlay |
| **iOS client** | Yes (Tailscale app) | Yes (native) | Yes (native) | No | Yes (native) |
| **UDP / mosh** | Yes | Yes (private mode) | Yes | Yes | Yes |
| **Self-hosted** | Yes (single binary) | Yes (Docker + Traefik) | Yes (Docker + IdP) | Yes (Docker) | Partial |
| **Setup complexity** | Very low | Moderate-high | Moderate | Moderate | Low (cloud) / High (self) |
| **Proprietary deps** | None | None | External IdP needed | "Pro" features gated | Controller proprietary |
| **NAT traversal** | DERP relay | Gerbil (WG relay) | STUN/TURN (coturn) | WG + relay | ZT root servers |
| **Maturity** | 5+ years | 1.5 years | 5 years | 5 years | 13 years |
| **Best for** | Personal mesh VPN | Exposing web services | Enterprise mesh | Infrastructure | LAN emulation |

---

## Final Recommendation

### For iPad (Blink) -> Mac with mosh: **Headscale**

1. **Headscale on VPS** (92.134.242.73) — single Go binary, systemd service, 10-min setup
2. **Tailscale on Mac** — point to Headscale, always-on daemon
3. **Tailscale on iPad** — official iOS app, connect to same Headscale
4. **mosh from Blink** — connect to Mac's Tailscale IP (100.x.y.z), UDP flows natively through WireGuard mesh

Why not the others:
- **Pangolin**: Great for web service exposure (future use for self-hosted apps), but overkill for device mesh
- **NetBird**: Enterprise-grade but the mandatory IdP requirement adds friction
- **Netmaker**: No iOS client
- **ZeroTier**: Controller is not truly open source

### Future complementary setup

Headscale for device mesh (iPad/Mac/VPS connectivity) + Pangolin for exposing web services (dashboards, APIs) from home. They solve different problems and can coexist.

---

## Action Items

- [ ] Install Headscale on VPS (92.134.242.73)
- [ ] Configure Tailscale on Mac (point to Headscale)
- [ ] Configure Tailscale on iPad (iOS app, custom login server)
- [ ] Test mosh from Blink SSH over Tailscale mesh
- [ ] Optional: self-host DERP relay on VPS for faster relay fallback
- [ ] Bookmark Pangolin for future web service exposure needs
