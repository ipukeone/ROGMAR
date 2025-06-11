#!/bin/bash
set -euo pipefail

# Config from env, mandatory variables
MYSQL_DB_HOST="${MYSQL_DB_HOST:?MYSQL_DB_HOST is required}"
MYSQL_USER="${MYSQL_USER:?MYSQL_USER is required}"
MYSQL_PASSWORD_FILE="${MYSQL_PASSWORD_FILE:?MYSQL_PASSWORD_FILE is required}"
MYSQL_DATABASE="${MYSQL_DATABASE:?MYSQL_DATABASE is required}"
RESTORE_DIR="/restore"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
}

# Check restore dir exists and readable
if [ ! -d "$RESTORE_DIR" ]; then
  log "Restore directory $RESTORE_DIR does not exist, creating..."
  mkdir -p "$RESTORE_DIR"
fi
if [ ! -r "$RESTORE_DIR" ]; then
  log "ERROR: Restore directory $RESTORE_DIR is not readable"
  exit 1
fi

# Lockfile to avoid parallel runs
LOCKFILE="/tmp/restore-cron.lock"
if [ -e "$LOCKFILE" ]; then
  log "Restore already running, exiting"
  exit 0
fi
trap 'rm -f "$LOCKFILE"' EXIT
touch "$LOCKFILE"

# List all backup files (sorted by name)
mapfile -t BACKUP_FILES < <(find "$RESTORE_DIR" -type f -name 'backup-*.sql.gz' | sort)

if [ "${#BACKUP_FILES[@]}" -eq 0 ]; then
  log "No backup files found in $RESTORE_DIR, exiting"
  exit 0
fi

# Create temporary MySQL config file with password
MYSQL_CNF=$(mktemp)
chmod 600 "$MYSQL_CNF"
cat > "$MYSQL_CNF" <<EOF
[client]
host=$MYSQL_DB_HOST
user=$MYSQL_USER
password=$(cat "$MYSQL_PASSWORD_FILE")
EOF

# Drop & recreate DB before restore
log "Dropping and recreating database '$MYSQL_DATABASE'"
mysql --defaults-extra-file="$MYSQL_CNF" -e "DROP DATABASE IF EXISTS \`$MYSQL_DATABASE\`;"
mysql --defaults-extra-file="$MYSQL_CNF" -e "CREATE DATABASE \`$MYSQL_DATABASE\`;"

# Restore all backups in order
for BACKUP in "${BACKUP_FILES[@]}"; do
  log "Restoring from $BACKUP"
  if gunzip -c "$BACKUP" | mysql --defaults-extra-file="$MYSQL_CNF" "$MYSQL_DATABASE"; then
    log "Restored: $BACKUP"
  else
    log "ERROR: Restore failed for $BACKUP"
    rm -f "$MYSQL_CNF"
    exit 1
  fi
done

rm -f "$MYSQL_CNF"
log "All restores completed successfully. Exiting."