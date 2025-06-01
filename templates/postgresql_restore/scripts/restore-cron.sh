#!/bin/sh
set -eu

: "${DB_HOST:?Missing DB_HOST}"
: "${POSTGRES_USER:?Missing POSTGRES_USER}"
: "${POSTGRES_DB:?Missing POSTGRES_DB}"
: "${POSTGRES_PASSWORD_FILE:?Missing POSTGRES_PASSWORD_FILE}"

RESTORE_DIR="/restore"

if [ ! -d "$RESTORE_DIR" ]; then
  echo "[INFO] No restore directory found at $RESTORE_DIR – nothing to do."
  exit 0
fi

if [ ! -f "$POSTGRES_PASSWORD_FILE" ]; then
  echo "[ERROR] Password file not found at $POSTGRES_PASSWORD_FILE"
  exit 1
fi

PGPASSWORD="$(cat "$POSTGRES_PASSWORD_FILE)"

found_files=false

for file in "$RESTORE_DIR"/*.sql; do
  if [ ! -e "$file" ]; then
    continue  # No .sql files matched
  fi

  found_files=true
  echo "[INFO] Restoring file: $file → DB '$POSTGRES_DB'"

  if PGPASSWORD="$PGPASSWORD" psql -h "$DB_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$file"; then
    echo "[INFO] Successfully restored: $file"
    rm -f "$file"
  else
    echo "[ERROR] Failed to restore: $file" >&2
    exit 1  # Stop on first error (fail-safe)
  fi
done

if [ "$found_files" = false ]; then
  echo "[INFO] No .sql files found in $RESTORE_DIR – nothing to do."
fi