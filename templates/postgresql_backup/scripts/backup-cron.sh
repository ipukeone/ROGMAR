#!/bin/sh
set -eu

: "${POSTGRES_USER:?Missing POSTGRES_USER}"
: "${POSTGRES_DB:?Missing POSTGRES_DB}"
: "${BACKUP_INTERVAL_HOURS:?Missing BACKUP_INTERVAL_HOURS}"
: "${BACKUP_KEEP:?Missing BACKUP_KEEP}"

BACKUP_INTERVAL_SECONDS=$((BACKUP_INTERVAL_HOURS * 3600))

echo "[INFO] Backup cron started. Interval: ${BACKUP_INTERVAL_HOURS}h (${BACKUP_INTERVAL_SECONDS}s), Keep last ${BACKUP_KEEP} backups"

while true; do
  timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
  backup_file="/backup/${POSTGRES_DB}_backup-${timestamp}.sql"

  echo "[INFO] Creating backup: $backup_file"
  if pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" > "$backup_file"; then
    echo "[INFO] Backup successful: $backup_file"
  else
    echo "[ERROR] Backup failed!" >&2
    rm -f "$backup_file"
  fi

  # Cleanup old backups
  echo "[INFO] Cleaning up old backups (keep latest ${BACKUP_KEEP})..."
  find /backup -maxdepth 1 -name "${POSTGRES_DB}_backup-*.sql" \
    | sort \
    | head -n -"$BACKUP_KEEP" \
    | while read -r old_file; do
        echo "[INFO] Removing old backup: $old_file"
        rm -f "$old_file"
      done

  echo "[INFO] Sleeping for ${BACKUP_INTERVAL_SECONDS} seconds..."
  sleep "$BACKUP_INTERVAL_SECONDS"
done