#!/bin/bash
# ACC v3 — PostgreSQL Restore Script
# Restores the database from a backup file
#
# Usage:
#   ./scripts/restore-db.sh                        # Interactive: pick from list
#   ./scripts/restore-db.sh backups/acc-2026-02-27_18-00.sql.gz  # Specific file

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACC_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$ACC_DIR/backups"
CONTAINER_NAME="acc-v3-db-1"
DB_USER="acc"
DB_NAME="acc"

echo "=== ACC v3 Database Restore ==="

# Check container
if ! docker ps --format '{{.Names}}' | grep -q "$CONTAINER_NAME"; then
  echo "ERROR: Container $CONTAINER_NAME is not running"
  exit 1
fi

# Select backup file
BACKUP_FILE=""
if [ $# -gt 0 ]; then
  # Specific file provided
  BACKUP_FILE="$1"
  if [[ ! "$BACKUP_FILE" = /* ]]; then
    BACKUP_FILE="$ACC_DIR/$BACKUP_FILE"
  fi
else
  # Interactive: list available backups
  echo ""
  echo "Available backups:"
  BACKUPS=($(ls -1t "$BACKUP_DIR"/acc-*.sql.gz 2>/dev/null))

  if [ ${#BACKUPS[@]} -eq 0 ]; then
    echo "  No backups found in $BACKUP_DIR"
    exit 1
  fi

  for i in "${!BACKUPS[@]}"; do
    SIZE=$(du -h "${BACKUPS[$i]}" | cut -f1)
    NAME=$(basename "${BACKUPS[$i]}")
    echo "  [$i] $NAME ($SIZE)"
  done

  echo ""
  read -p "Select backup number [0]: " CHOICE
  CHOICE=${CHOICE:-0}

  if [ "$CHOICE" -ge ${#BACKUPS[@]} ] 2>/dev/null; then
    echo "ERROR: Invalid selection"
    exit 1
  fi

  BACKUP_FILE="${BACKUPS[$CHOICE]}"
fi

if [ ! -f "$BACKUP_FILE" ]; then
  echo "ERROR: Backup file not found: $BACKUP_FILE"
  exit 1
fi

SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
echo ""
echo "Restoring from: $(basename "$BACKUP_FILE") ($SIZE)"
echo ""
echo "WARNING: This will REPLACE all current data in the '$DB_NAME' database."
read -p "Are you sure? [y/N]: " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
  echo "Aborted."
  exit 0
fi

# Create a safety backup before restore
SAFETY_FILE="$BACKUP_DIR/acc-pre-restore-$(date +%Y-%m-%d_%H-%M).sql.gz"
echo ""
echo "Creating safety backup before restore..."
docker exec "$CONTAINER_NAME" pg_dump -U "$DB_USER" -d "$DB_NAME" \
  --clean --if-exists --no-owner --no-privileges \
  | gzip > "$SAFETY_FILE"
echo "Safety backup: $SAFETY_FILE"

# Restore
echo ""
echo "Restoring database..."
gunzip -c "$BACKUP_FILE" | docker exec -i "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -q 2>&1 | tail -5

# Verify
echo ""
echo "Verification — row counts after restore:"
docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -t -A -c "
SELECT 'memories: ' || COUNT(*) FROM agent_memories
UNION ALL SELECT 'events: ' || COUNT(*) FROM agent_events
UNION ALL SELECT 'chats: ' || COUNT(*) FROM chat_messages
UNION ALL SELECT 'agents: ' || COUNT(*) FROM agents
UNION ALL SELECT 'sessions: ' || COUNT(*) FROM sessions;
"

echo ""
echo "=== Restore complete ==="
echo "Safety backup kept at: $SAFETY_FILE"
