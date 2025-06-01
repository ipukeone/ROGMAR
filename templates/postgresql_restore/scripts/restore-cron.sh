#!/bin/sh
set -eu

: "${DB_HOST:?Missing DB_HOST}"
: "${POSTGRES_USER:?Missing POSTGRES_USER}"
: "${POSTGRES_DB:?Missing POSTGRES_DB}"
: "${POSTGRES_RESTORE_FILENAME:?Missing POSTGRES_RESTORE_FILENAME}"
: "${POSTGRES_PASSWORD_FILE:?Missing POSTGRES_PASSWORD_FILE}"

RESTORE_FILE="/restore/$POSTGRES_RESTORE_FILENAME"

if [ -f "$RESTORE_FILE" ]; then
  echo "[INFO] Restore file found: $RESTORE_FILE – starting restore into DB '$POSTGRES_DB'..."

  if [ ! -f "$POSTGRES_PASSWORD_FILE" ]; then
    echo "[ERROR] Password file not found at $POSTGRES_PASSWORD_FILE"
    exit 1
  fi

  PGPASSWORD="$(cat "$POSTGRES_PASSWORD_FILE")" \
    psql -h "$DB_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$RESTORE_FILE"

  echo "[INFO] Restore finished, removing restore file"
  rm -f "$RESTORE_FILE"
else
  echo "[INFO] No restore file found at $RESTORE_FILE – nothing to do."
fi