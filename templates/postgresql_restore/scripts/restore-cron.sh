#!/bin/sh
set -eu

: "${POSTGRES_USER:?Missing POSTGRES_USER}"
: "${POSTGRES_DB:?Missing POSTGRES_DB}"

RESTORE_FILENAME="${POSTGRES_RESTORE_FILENAME:?Missing POSTGRES_RESTORE_FILENAME}"
RESTORE_FILE="/restore/$RESTORE_FILENAME"

if [ -f "$RESTORE_FILE" ]; then
  echo "[INFO] Restore file found: $RESTORE_FILE – starting restore into DB '$POSTGRES_DB'..."
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$RESTORE_FILE"
  echo "[INFO] Restore finished, removing restore file"
  rm -f "$RESTORE_FILE"
else
  echo "[INFO] No restore file found at $RESTORE_FILE – nothing to do."
fi