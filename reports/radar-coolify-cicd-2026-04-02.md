# Radar: Coolify -- Self-Hosted PaaS & CI/CD Platform

**Date**: 2026-04-02
**Source**: https://github.com/coollabsio/coolify (52.5k stars, Apache-2.0)
**Category**: Infrastructure / Deployment / CI-CD
**Verdict**: WATCH -- useful patterns, but architectural mismatch with Shikki production model

---

## 1. Coolify Architecture Summary

### What it is
Coolify is an open-source, self-hosted PaaS (Heroku/Vercel alternative). It manages servers, applications, databases, and services via SSH. You install Coolify on one server, then it deploys to that server or additional remote servers.

### Tech stack
- **Backend**: Laravel 12 (PHP 8.4) + PostgreSQL 15 + Redis 7
- **Frontend**: Livewire 3 + Alpine.js + Tailwind CSS v4
- **Realtime**: Soketi (WebSocket server)
- **Process supervisor**: S6 Overlay
- **Proxy**: Traefik (auto-managed per server)
- **Monitoring**: "Sentinel" -- lightweight Docker container on each managed server that reports metrics back to Coolify

### Deployment model (Docker-centric)
Coolify is fundamentally Docker-based. Every deployed application runs as a Docker container. It supports multiple build strategies:

| Build Pack | How it works |
|---|---|
| **Nixpacks** | Auto-detects language, generates Dockerfile, builds container (default) |
| **Dockerfile** | Uses your Dockerfile directly |
| **Docker Compose** | Deploys multi-service stacks |
| **Docker Image** | Pulls pre-built image from registry |
| **Static** | Nginx container serving static files |

### Change detection & triggers
- **Webhook-based**: GitHub/GitLab/Bitbucket/Gitea push events trigger deployments
- **GitHub App integration**: Full OAuth flow with HMAC-SHA256 signature verification
- **API-triggered**: `POST /api/v1/deploy` with bearer token (can deploy by UUID, tag, or project)
- **Manual**: Web UI "Deploy" button
- No polling -- pure webhook + API architecture

### Build pipeline (ApplicationDeploymentJob -- 4,255 lines)
1. Verify server is functional (SSH reachable)
2. Detect BuildKit capabilities
3. Choose build strategy (`decide_what_to_do()`)
4. Clone repo into builder container
5. Generate build-time env vars (secrets injected as Docker build secrets if BuildKit available)
6. Build image (Nixpacks/Dockerfile/compose)
7. Push to Docker registry (if build server != deploy server)
8. Generate runtime env vars
9. Generate docker-compose.yml with labels (Traefik routing, healthcheck config)
10. Rolling update: start new container, health check, stop old container
11. Post-deployment: notifications (Discord, Slack, Telegram, Pushover, webhooks)

### Rollback model
- **Swarm mode**: Docker Swarm native `rollback_config` with `order: start-first`
- **Non-swarm**: Manual rollback by re-deploying a previous commit (redeploy with `rollback: true` flag)
- No automatic rollback on health check failure -- the unhealthy container stays, old container is already stopped

### Health checks
- Configurable per application: HTTP path, CMD, custom port, interval, retries, start period
- Docker HEALTHCHECK directive respected if found in Dockerfile
- Health check runs inside the container, not from Coolify

### Secret management
- Environment variables stored encrypted in PostgreSQL (`ShouldBeEncrypted` on all queue jobs)
- Build-time vs runtime separation
- Shared environment variables across environments
- No external vault integration (no HashiCorp Vault, no SOPS)

### Monitoring (Sentinel)
- Lightweight Docker container auto-deployed on each managed server
- Reports container status, resource usage back to Coolify
- Auto-updated when new versions are available
- Healthcheck via `curl http://127.0.0.1:8888/api/version`

---

## 2. Comparison: Coolify vs Current `shi ship` Pipeline

| Capability | Coolify | Shikki `shi ship` |
|---|---|---|
| **Build trigger** | Webhook + API + UI | CLI-driven (`shikki ship`) |
| **Pre-deploy quality gates** | None (just builds) | 12 gates: CTO review, slop scan, tests, lint, branch check, tag, changelog, etc. |
| **Test execution** | Not part of pipeline (delegated to CI) | TestGate runs `swift test` as hard gate |
| **Code review** | None | CtoReviewGate (LLM-assisted, Swift-judged) |
| **Build system** | Docker build (Nixpacks/Dockerfile) | `swift build` for native binaries |
| **Deployment target** | Docker containers via SSH | systemd services (native binaries), TestFlight (iOS) |
| **Proxy/routing** | Auto-managed Traefik | Caddy (manually configured) |
| **Rolling update** | Yes (start new, health check, stop old) | No (manual `systemctl restart`) |
| **Health checks** | Configurable HTTP/CMD per app | None post-deploy |
| **Rollback** | Manual re-deploy of previous commit | None |
| **Event bus** | WebSocket (Soketi) for UI updates | ShikkiEvent protocol, full event pipeline |
| **Multi-environment** | Team > Project > Environment hierarchy | Branch-based (`develop`, `release/*`, `main`) |
| **Secret management** | Encrypted PostgreSQL | `.envrc` + systemd EnvironmentFile |
| **Notifications** | Discord, Slack, Telegram, Pushover, custom webhook | ntfy.sh with approve/deny buttons |
| **API** | Full REST API (OpenAPI documented) | CLI only |
| **Spec-driven development** | No | Yes (/spec pipeline, frontmatter tracking) |
| **Multi-agent review** | No | @Sensei, @Ronin, @Metsuke agents |

---

## 3. What Coolify Does That Shikki Doesn't

1. **Rolling updates with health checks**: Start new version, verify healthy, then stop old. Shikki does `systemctl restart` with no overlap period.
2. **Webhook-triggered deploys**: Push to GitHub, automatic deployment. Shikki requires manual `shikki ship` invocation.
3. **Multi-server management via SSH**: Deploy to N servers from one control plane. Shikki targets a single VPS.
4. **Auto-managed reverse proxy (Traefik)**: SSL certs, routing labels, zero-config. Shikki uses manually-configured Caddy.
5. **Deployment queue with concurrency control**: `WithoutOverlapping` middleware prevents parallel deploys to same server.
6. **Build server separation**: Can build on a beefy server, deploy to a small one. Shikki builds on the target.
7. **Database backup scheduling**: Automated PostgreSQL/MySQL backups with S3 storage.
8. **Full REST API for deployment automation**: Any tool can trigger deploys via `POST /api/v1/deploy`.

---

## 4. What Shikki Does That Coolify Doesn't

1. **Spec-driven pipeline**: Every feature starts with `/spec`, goes through frontmatter-tracked lifecycle. Coolify has zero concept of feature specs.
2. **Multi-agent quality review**: CTO review gate, slop scan, @Ronin adversarial review. Coolify deploys whatever you push -- no quality judgment.
3. **TDD enforcement**: TestGate is a hard gate. Coolify assumes tests run elsewhere (GitHub Actions).
4. **Compiled gate logic**: Swift code makes pass/fail decisions. LLM is a worker, not the judge. Coolify has no programmable gate system.
5. **Event bus architecture**: ShikkiEvent protocol streams every pipeline action. Coolify uses WebSockets only for UI updates.
6. **Native binary deployment**: `swift build` produces a single binary. No Docker layer, no container runtime overhead. Coolify requires Docker on every target.
7. **Attribution tracking**: Co-Authored-By, Orchestrated-By headers. Coolify has no concept of agent attribution.

---

## 5. Recommendation

**Verdict: WATCH -- do not adopt.**

Coolify is an excellent self-hosted PaaS for teams deploying Docker-based web applications. Its 52k stars reflect genuine value for that use case. However, it is a poor fit for Shikki's production model for three reasons:

**1. Docker-in-prod conflict.** Shikki's production philosophy is native binaries as systemd services -- no Docker runtime in production. Coolify's entire deployment model assumes Docker containers. Adopting Coolify would mean reversing a deliberate architectural decision. The overhead of running Docker daemon + Traefik + Sentinel on a VPS that currently runs just PocketBase + Caddy is not justified.

**2. No quality gate system.** Coolify deploys whatever passes `docker build`. It has no concept of pre-deploy quality gates, test enforcement, spec validation, or code review. Shikki's 12-gate pipeline with LLM-assisted CTO review and slop scanning is far more sophisticated. Coolify would replace the strong part (quality gates) with nothing, while adding value only on the weak part (actual deployment mechanics).

**3. Wrong abstraction level.** Coolify manages "applications" as long-running Docker services with Traefik routing. Shikki manages "features" through a lifecycle from spec to ship. These are different abstractions. Integrating them would require a translation layer that adds complexity without proportional value.

**What to steal instead** (patterns, not the tool):

- Rolling update pattern (start new, health check, stop old) -- implement natively in `ShipService`
- Webhook-triggered deploys -- add to `shi ship` as an optional trigger mode
- Deployment queue with concurrency control -- prevent parallel deploys

---

## 6. Actionable Items for Shikki Backlog (max 3)

### [P1] Rolling Deploy Gate -- zero-downtime systemd restart
Steal Coolify's rolling update pattern but for systemd services:
1. Build new binary to a staged path (`/opt/shikki/bin/pocketbase.next`)
2. Start new instance on a temp port
3. Health check the new instance (`curl -sf http://localhost:TEMP_PORT/api/health`)
4. If healthy: swap symlink, `systemctl reload`, stop temp instance
5. If unhealthy: delete staged binary, emit `shipGateFailed` event, abort

This fills the biggest gap identified in the comparison. No Docker required.

**Files to modify**: New `RollingDeployGate` conforming to `ShipGate` protocol in `ShipGate.swift`.

### [P1] Post-Deploy Health Check Gate
Add a `HealthCheckGate` that runs after deployment (index 8, after all current gates):
- Configurable HTTP endpoint + expected status code
- Configurable CMD check (e.g., `pocketbase version`)
- Retry logic with interval/retries/timeout (steal Coolify's exact pattern)
- On failure: emit event + ntfy notification with "Rollback?" action button

**Files to modify**: New gate in `ShipGate.swift`, wire into `ShipService.swift`.

### [P2] Deploy API Endpoint -- webhook-triggered ship
Add a lightweight HTTP endpoint (or extend ShikkiMCP) that accepts deploy triggers:
- `POST /api/deploy` with branch + target parameters
- Validates webhook signature (HMAC-SHA256, same pattern as Coolify's GitHub webhook handler)
- Queues a `shikki ship` run with concurrency guard (only one deploy per target at a time)
- Returns deployment UUID for status polling

This enables GitHub Actions to trigger `shi ship` after CI passes, closing the manual gap without adopting Coolify's full stack.

**Files to modify**: New endpoint in ShikkiMCP or standalone HTTP listener.

---

## 7. Key Source References (Coolify)

| File | What it contains |
|---|---|
| `app/Jobs/ApplicationDeploymentJob.php` (4,255 lines) | Full build + deploy pipeline, rolling update, health check |
| `routes/webhooks.php` | GitHub/GitLab/Bitbucket/Gitea webhook endpoints |
| `app/Http/Controllers/Webhook/Github.php` | Push + PR event handling, HMAC validation |
| `app/Http/Controllers/Api/DeployController.php` | REST API for triggering deploys |
| `app/Jobs/ServerCheckJob.php` | Server health monitoring, Sentinel management |
| `app/Jobs/CheckAndStartSentinelJob.php` | Monitoring agent auto-update |
| `docker-compose.prod.yml` | Coolify's own production stack (Laravel + PG + Redis + Soketi) |
| `CLAUDE.md` | Full architecture overview, domain model, conventions |
