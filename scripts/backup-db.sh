#!/bin/bash
# Shiki — PostgreSQL Backup Script
# Backs up the database to a timestamped SQL dump
#
# Usage:
#   ./scripts/backup-db.sh              # Manual backup
#   crontab: 0 18 * * * /path/to/backup-db.sh   # Auto at 6pm
#
# Backups go to: backups/shiki-YYYY-MM-DD_HH-MM.sql.gz

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHIKI_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$SHIKI_DIR/backups"
CONTAINER_NAME="shiki-db-1"
DB_USER="acc"
DB_NAME="acc"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M)
BACKUP_FILE="$BACKUP_DIR/shiki-${TIMESTAMP}.sql.gz"

# Retention: keep last 14 days
RETENTION_DAYS=14

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

echo "=== Shiki Database Backup ==="
echo "Time: $(date)"
echo "Target: $BACKUP_FILE"

# Check container is running
if ! docker ps --format '{{.Names}}' | grep -q "$CONTAINER_NAME"; then
  echo "ERROR: Container $CONTAINER_NAME is not running"
  exit 1
fi

# Get row counts before backup
echo ""
echo "Database stats:"
docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -t -A -c "
SELECT 'memories: ' || COUNT(*) FROM agent_memories
UNION ALL SELECT 'events: ' || COUNT(*) FROM agent_events
UNION ALL SELECT 'chats: ' || COUNT(*) FROM chat_messages
UNION ALL SELECT 'agents: ' || COUNT(*) FROM agents
UNION ALL SELECT 'sessions: ' || COUNT(*) FROM sessions
UNION ALL SELECT 'decisions: ' || COUNT(*) FROM decisions
UNION ALL SELECT 'git_events: ' || COUNT(*) FROM git_events
UNION ALL SELECT 'metrics: ' || COUNT(*) FROM performance_metrics;
"

# Dump and compress
echo ""
echo "Dumping..."
docker exec "$CONTAINER_NAME" pg_dump -U "$DB_USER" -d "$DB_NAME" \
  --clean --if-exists --no-owner --no-privileges \
  | gzip > "$BACKUP_FILE"

SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
echo "Backup complete: $BACKUP_FILE ($SIZE)"

# Cleanup old backups
echo ""
echo "Cleaning up backups older than ${RETENTION_DAYS} days..."
DELETED=$(find "$BACKUP_DIR" -name "shiki-*.sql.gz" -mtime +${RETENTION_DAYS} -print -delete | wc -l)
echo "Deleted $DELETED old backups"

# List current backups
echo ""
echo "Current backups:"
ls -lh "$BACKUP_DIR"/shiki-*.sql.gz 2>/dev/null | awk '{print "  " $NF " (" $5 ")"}'

echo ""
echo "=== Done ==="
