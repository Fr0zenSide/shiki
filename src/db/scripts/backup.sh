#!/usr/bin/env bash
set -euo pipefail
BACKUP_DIR="${1:-./backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_DIR"
docker compose exec -T db pg_dump -U "${POSTGRES_USER:-shiki}" -d "${POSTGRES_DB:-shiki}" --format=custom --compress=9 > "$BACKUP_DIR/shiki_${TIMESTAMP}.dump"
echo "Backup saved: $BACKUP_DIR/shiki_${TIMESTAMP}.dump"
ls -lh "$BACKUP_DIR/shiki_${TIMESTAMP}.dump"
