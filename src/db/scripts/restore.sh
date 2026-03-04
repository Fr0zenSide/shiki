#!/usr/bin/env bash
set -euo pipefail
BACKUP_FILE="${1:?Usage: restore.sh <backup_file>}"
[ ! -f "$BACKUP_FILE" ] && echo "File not found: $BACKUP_FILE" && exit 1
echo "Restoring from: $BACKUP_FILE"
docker compose exec -T db pg_restore -U "${POSTGRES_USER:-shiki}" -d "${POSTGRES_DB:-shiki}" --clean --if-exists < "$BACKUP_FILE"
echo "Restore complete."
