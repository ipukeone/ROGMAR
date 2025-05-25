#!/usr/bin/env bash
set -euo pipefail

# Add initdb settings into this file if needed!

# echo "Enabling pg_trgm extension in database: ${POSTGRES_DB}"

# psql -v ON_ERROR_STOP=1 \
#      -U "${POSTGRES_USER}" \
#      -d "${POSTGRES_DB}" <<-'SQL'
#   CREATE EXTENSION IF NOT EXISTS pg_trgm;
# SQL

# echo "pg_trgm extension setup completed successfully."