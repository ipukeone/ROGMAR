#!/bin/sh
set -eu

: "${DB_HOST:?Missing DB_HOST}"
: "${POSTGRES_USER:?Missing POSTGRES_USER}"
: "${POSTGRES_DB:?Missing POSTGRES_DB}"
: "${POSTGRES_PASSWORD_FILE:?Missing POSTGRES_PASSWORD_FILE}"
: "${POSTGRES_BACKUP_INTERVAL_HOURS:?Missing POSTGRES_BACKUP_INTERVAL_HOURS}"
: "${POSTGRES_BACKUP_KEEP:?Missing POSTGRES_BACKUP_KEEP}"

BACKUP_INTERVAL_SECONDS=$((POSTGRES_BACKUP_INTERVAL_HOURS * 3600))

echo "[INFO] Backup cron started. Interval: ${POSTGRES_BACKUP_INTERVAL_HOURS}h (${BACKUP_INTERVAL_SECONDS}s), Keep last ${POSTGRES_BACKUP_KEEP} backups"

while true; do
  timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
  backup_file="/backup/${POSTGRES_DB}_backup-${timestamp}.sql"

  if [ ! -f "$POSTGRES_PASSWORD_FILE" ]; then
    echo "[ERROR] Password file not found at $POSTGRES_PASSWORD_FILE" >&2
    exit 1
  fi

  echo "[INFO] Creating backup: $backup_file"
  if PGPASSWORD="$(cat "$POSTGRES_PASSWORD_FILE")" \
     pg_dump -h "$DB_HOST" -U "$POSTGRES_USER" "$POSTGRES_DB" > "$backup_file"; then
    echo "[INFO] Backup successful: $backup_file"
  else
    echo "[ERROR] Backup failed!" >&2
    rm -f "$backup_file"
  fi

  # Cleanup old backups
  echo "[INFO] Cleaning up old backups (keep latest ${POSTGRES_BACKUP_KEEP})..."
  find /backup -maxdepth 1 -name "${POSTGRES_DB}_backup-*.sql" \
    | sort \
    | head -n -"$POSTGRES_BACKUP_KEEP" \
    | while read -r old_file; do
        echo "[INFO] Removing old backup: $old_file"
        rm -f "$old_file"
      done

  echo "[INFO] Sleeping for ${BACKUP_INTERVAL_SECONDS} seconds..."
  sleep "$BACKUP_INTERVAL_SECONDS"
done