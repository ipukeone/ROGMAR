#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Validate required environment variables
# -----------------------------------------------------------------------------
: "${DB_HOST:?Missing DB_HOST}"
: "${POSTGRES_USER:?Missing POSTGRES_USER}"
: "${POSTGRES_DB:?Missing POSTGRES_DB}"
: "${POSTGRES_PASSWORD_FILE:?Missing POSTGRES_PASSWORD_FILE}"

# -----------------------------------------------------------------------------
# Check password file exists
# -----------------------------------------------------------------------------
if [ ! -f "$POSTGRES_PASSWORD_FILE" ]; then
  echo "[ERROR] Password file not found at: $POSTGRES_PASSWORD_FILE" >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# Enable pg_trgm extension in the target database
# -----------------------------------------------------------------------------
echo "[INFO] Enabling pg_trgm extension in database: $POSTGRES_DB"

if ! PGPASSWORD="$(< "$POSTGRES_PASSWORD_FILE")" \
     psql -v ON_ERROR_STOP=1 \
          -U "$POSTGRES_USER" \
          -d "$POSTGRES_DB" \
          -h "$DB_HOST" \
          -c 'CREATE EXTENSION IF NOT EXISTS pg_trgm;'; then
  echo "[ERROR] Failed to enable pg_trgm extension." >&2
  exit 1
fi

echo "[INFO] pg_trgm extension setup completed successfully."