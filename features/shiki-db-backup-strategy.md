# Feature: Shiki DB Backup — Encrypted, Self-Hosted, No External Actors

> **Type**: /spec
> **Priority**: P0 — knowledge is the most valuable asset, must be protected NOW
> **Status**: Spec (validated by @Daimyo 2026-03-18)
> **Depends on**: Shiki DB (existing), VPS (92.134.242.73, existing)

---

## 1. Problem

Shiki DB contains all decisions, plans, agent reports, session history, and knowledge graph data. If the DB is lost:
- Every architecture decision from every session is gone
- Agent effectiveness data (future flywheel) is gone
- Audit trail for enterprise safety is gone
- Context for all projects is gone

Currently: zero backups. PostgreSQL data lives only in the Docker volume on the local machine. One disk failure = total loss.

**Additional constraint**: this knowledge must NOT be stored on GitHub or any external service. It contains proprietary project data, company strategies, and potentially sensitive business logic. Only the user's own infrastructure (VPS) is trusted.

## 2. Solution — Encrypted Backups to VPS

```
Local Mac (PostgreSQL in Docker)
    ↓ pg_dump (nightly + on-demand)
    ↓ gpg encrypt (AES-256)
    ↓ rsync over SSH
    ↓
VPS (92.134.242.73)
    └── /srv/backups/shiki-db/
        ├── 2026-03-18-daily.sql.gpg
        ├── 2026-03-17-daily.sql.gpg
        ├── 2026-03-15-weekly.sql.gpg
        └── latest.sql.gpg → symlink to newest
```

## 3. Backup Pipeline

### 3.1 Dump

```bash
# pg_dump from Docker container
docker exec shiki-db-1 pg_dump -U postgres shiki \
  --format=custom --compress=9 \
  > /tmp/shiki-db-backup.dump
```

`--format=custom` for efficient restore. `--compress=9` for smallest size.

### 3.2 Encrypt

```bash
# GPG symmetric encryption (passphrase from env)
gpg --batch --yes --symmetric \
  --cipher-algo AES256 \
  --passphrase-file ~/.config/shiki/backup-passphrase \
  --output /tmp/shiki-db-$(date +%Y-%m-%d).sql.gpg \
  /tmp/shiki-db-backup.dump

# Clean up unencrypted dump
rm /tmp/shiki-db-backup.dump
```

### 3.3 Transfer

```bash
# rsync to VPS over SSH
rsync -az --progress \
  /tmp/shiki-db-$(date +%Y-%m-%d).sql.gpg \
  vps:/srv/backups/shiki-db/

# Update latest symlink
ssh vps "ln -sf /srv/backups/shiki-db/shiki-db-$(date +%Y-%m-%d).sql.gpg \
  /srv/backups/shiki-db/latest.sql.gpg"
```

### 3.4 Verify

```bash
# Verify backup is valid (decrypt + pg_restore --list)
ssh vps "gpg --batch --decrypt \
  --passphrase-file /root/.config/shiki/backup-passphrase \
  /srv/backups/shiki-db/latest.sql.gpg | \
  pg_restore --list > /dev/null && echo 'VALID' || echo 'CORRUPT'"
```

## 4. Retention Policy

| Type | Frequency | Retention | Count |
|------|-----------|-----------|-------|
| Daily | Every night at 3AM | 7 days | ~7 |
| Weekly | Sunday 3AM | 4 weeks | ~4 |
| Monthly | 1st of month | 6 months | ~6 |

Pruning script runs after each backup, removes expired files.

Total storage estimate: ~17 backups × ~50MB = ~850MB max.

## 5. Automation

### Option A: Cron on local Mac (simplest)

```cron
# ~/.config/shiki/crontab
0 3 * * * /Users/jeoffrey/.local/bin/shiki backup --quiet
0 3 * * 0 /Users/jeoffrey/.local/bin/shiki backup --weekly --quiet
0 3 1 * * /Users/jeoffrey/.local/bin/shiki backup --monthly --quiet
```

### Option B: `shiki backup` command (preferred)

```bash
shiki backup              # run backup now
shiki backup --schedule   # install cron jobs
shiki backup --verify     # verify latest backup
shiki backup --restore    # restore from latest (interactive)
shiki backup --list       # show all backups with dates + sizes
```

### Option C: Hook into `shiki down`

Before stopping the system, auto-backup:

```bash
shiki down  →  backup  →  stop containers  →  done
```

## 6. Restore Procedure

```bash
# 1. Download from VPS
scp vps:/srv/backups/shiki-db/latest.sql.gpg /tmp/

# 2. Decrypt
gpg --batch --decrypt \
  --passphrase-file ~/.config/shiki/backup-passphrase \
  /tmp/latest.sql.gpg > /tmp/shiki-restore.dump

# 3. Restore into running PostgreSQL
docker exec -i shiki-db-1 pg_restore \
  -U postgres -d shiki --clean --if-exists \
  < /tmp/shiki-restore.dump

# 4. Verify
curl -s http://localhost:3900/health
shiki status
```

## 7. Security Model

| Aspect | Implementation |
|--------|---------------|
| Encryption at rest | AES-256 (GPG symmetric) |
| Key storage | `~/.config/shiki/backup-passphrase` (600 perms, never in git) |
| Transfer encryption | SSH (rsync over SSH tunnel) |
| VPS access | SSH key only (no password auth) |
| No external actors | Backups ONLY on user's VPS, never GitHub/S3/cloud |
| Passphrase rotation | Manual, documented in `shiki backup --rotate-key` |

## 8. Monitoring

### ntfy alerts

```bash
# After backup, notify
shiki notify "Backup complete: $(du -h /tmp/shiki-db-*.gpg | tail -1)"

# On failure
shiki notify --priority high "Backup FAILED: $error"
```

### Health check

Weekly `shiki backup --verify` via cron. If verification fails → ntfy alert.

## 9. Deliverables

- `shiki backup` command (BackupCommand.swift) — dump, encrypt, transfer, verify, restore
- `scripts/shiki-backup.sh` — shell script for cron (fallback if binary not available)
- `~/.config/shiki/backup-passphrase` — generated on `shiki backup --setup`
- VPS directory structure at `/srv/backups/shiki-db/`
- Cron installation via `shiki backup --schedule`
- ntfy integration for success/failure alerts

## 10. What This Protects

| Data | Value | Recovery without backup |
|------|-------|----------------------|
| Architecture decisions | Irreplaceable — months of context | Gone forever |
| Agent effectiveness data | Flywheel fuel | Must rebuild from scratch |
| Session transcripts | Debug + audit trail | Gone |
| Plans + specs in DB | Traceable decision chain | Local .md files survive (partial) |
| Knowledge graph | Cross-project intelligence | Gone |
