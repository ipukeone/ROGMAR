#!/bin/bash
set -euo pipefail

# Config from env, mandatory variables will error out if missing
MYSQL_USER="${MYSQL_USER:?MYSQL_USER is required}"
MYSQL_DATABASE="${MYSQL_DATABASE:?MYSQL_DATABASE is required}"
MYSQL_PASSWORD_FILE="${MYSQL_PASSWORD_FILE:?MYSQL_PASSWORD_FILE is required}"
MYSQL_DB_HOST="${MYSQL_DB_HOST:?MYSQL_DB_HOST is required}"
MYSQL_BACKUP_INTERVAL_HOURS="${MYSQL_BACKUP_INTERVAL_HOURS:-2}"
MYSQL_BACKUP_KEEP="${MYSQL_BACKUP_KEEP:-5}"
BACKUP_DIR="/backup"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
}

# Ensure backup dir exists and writable
if [ ! -d "$BACKUP_DIR" ]; then
  log "Backup directory $BACKUP_DIR does not exist, creating..."
  mkdir -p "$BACKUP_DIR"
fi
if [ ! -w "$BACKUP_DIR" ]; then
  log "ERROR: Backup directory $BACKUP_DIR is not writable"
  exit 1
fi

while true; do
  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  BACKUP_FILE="$BACKUP_DIR/backup-$TIMESTAMP.sql.gz"
  log "Starting backup: $BACKUP_FILE"

  # Create a temporary MySQL config file to hide password from process list
  MYSQL_CNF=$(mktemp)
  chmod 600 "$MYSQL_CNF"
  cat > "$MYSQL_CNF" <<EOF
[client]
host=$MYSQL_DB_HOST
user=$MYSQL_USER
password=$(cat "$MYSQL_PASSWORD_FILE")
EOF

  if mysqldump --defaults-extra-file="$MYSQL_CNF" "$MYSQL_DATABASE" | gzip > "$BACKUP_FILE"; then
    log "Backup completed successfully"
  else
    log "ERROR: Backup failed"
    rm -f "$BACKUP_FILE"
    rm -f "$MYSQL_CNF"
    exit 1
  fi

  rm -f "$MYSQL_CNF"

  # Cleanup old backups
  BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/backup-*.sql.gz 2>/dev/null | wc -l || echo 0)
  if [ "$BACKUP_COUNT" -gt "$MYSQL_BACKUP_KEEP" ]; then
    log "Cleaning old backups, keeping $MYSQL_BACKUP_KEEP files..."
    ls -1t "$BACKUP_DIR"/backup-*.sql.gz | tail -n +$((MYSQL_BACKUP_KEEP + 1)) | xargs -r rm -f
  else
    log "No old backups to clean up (found $BACKUP_COUNT files)"
  fi

  log "Sleeping for $MYSQL_BACKUP_INTERVAL_HOURS hours..."
  sleep $((MYSQL_BACKUP_INTERVAL_HOURS * 3600))
done