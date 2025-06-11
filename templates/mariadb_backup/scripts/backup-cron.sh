#!/bin/bash
set -euo pipefail

# Config from environment variables or exit if missing
MYSQL_USER="${MYSQL_USER:?MYSQL_USER is required}"
MYSQL_PASSWORD_FILE="${MYSQL_PASSWORD_FILE:?MYSQL_PASSWORD_FILE is required}"
MYSQL_DB_HOST="${MYSQL_DB_HOST:?MYSQL_DB_HOST is required}"
MYSQL_BACKUP_INTERVAL_HOURS="${MYSQL_BACKUP_INTERVAL_HOURS:-2}"
MYSQL_BACKUP_KEEP="${MYSQL_BACKUP_KEEP:-5}"
BACKUP_DIR="/backup"

# Log helper function with timestamp
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
}

# Prepare backup directory: create if missing and check write permission
prepare_backup_dir() {
  if [ ! -d "$BACKUP_DIR" ]; then
    log "Backup directory $BACKUP_DIR does not exist, creating..."
    mkdir -p "$BACKUP_DIR"
  fi

  if [ ! -w "$BACKUP_DIR" ]; then
    log "ERROR: Backup directory $BACKUP_DIR is not writable"
    exit 1
  fi
}

# Remove old backups keeping only the configured number of backups
cleanup_old_backups() {
  local count current_to_delete

  count=$(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -name "backup-*" | wc -l || echo 0)

  if (( count > MYSQL_BACKUP_KEEP )); then
    current_to_delete=$(( count - MYSQL_BACKUP_KEEP ))
    log "Cleaning $current_to_delete old backup(s)..."
    find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -name "backup-*" | sort | head -n "$current_to_delete" | xargs -r rm -rf
  else
    log "No old backups to clean up (found $count backups)"
  fi
}

# Run mariadb-backup with given credentials and target directory
run_backup() {
  local timestamp backup_subdir mysql_password

  timestamp=$(date +%Y%m%d-%H%M%S)
  backup_subdir="$BACKUP_DIR/backup-$timestamp"
  log "Starting backup: $backup_subdir"

  mkdir -p "$backup_subdir"
  chmod 700 "$backup_subdir"

  mysql_password=$(< "$MYSQL_PASSWORD_FILE")

  if mariadb-backup \
      --host="$MYSQL_DB_HOST" \
      --user="$MYSQL_USER" \
      --password="$mysql_password" \
      --backup \
      --target-dir="$backup_subdir"; then
    log "Backup completed successfully"
  else
    log "ERROR: Backup failed"
    rm -rf "$backup_subdir"
    exit 1
  fi
}

# Main loop: run backup, clean old backups, then sleep for configured interval
main_loop() {
  while true; do
    run_backup
    cleanup_old_backups
    log "Sleeping for $MYSQL_BACKUP_INTERVAL_HOURS hours..."
    sleep $(( MYSQL_BACKUP_INTERVAL_HOURS * 3600 ))
  done
}

# Script execution starts here
prepare_backup_dir
main_loop