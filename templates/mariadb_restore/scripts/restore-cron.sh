#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------
MYSQL_DB_HOST="${MYSQL_DB_HOST:?MYSQL_DB_HOST is required}"
MYSQL_USER="${MYSQL_USER:?MYSQL_USER is required}"
MYSQL_PASSWORD_FILE="${MYSQL_PASSWORD_FILE:?MYSQL_PASSWORD_FILE is required}"
MYSQL_DATABASE="${MYSQL_DATABASE:?MYSQL_DATABASE is required}"
RESTORE_DIR="/restore"
LOCKFILE="/tmp/restore-cron.lock"
MYSQL_ROOT_PASSWORD_FILE="/run/secrets/MYSQL_ROOT_PASSWORD"  # Used for connectivity check

# -----------------------------------------------------------------------------
# LOGGING FUNCTION
# -----------------------------------------------------------------------------
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
}

# -----------------------------------------------------------------------------
# CHECK THAT RESTORE DIR EXISTS AND IS READABLE
# -----------------------------------------------------------------------------
prepare_restore_dir() {
  if [ ! -d "$RESTORE_DIR" ]; then
    log "Restore directory $RESTORE_DIR does not exist, creating..."
    mkdir -p "$RESTORE_DIR"
  fi
  if [ ! -r "$RESTORE_DIR" ]; then
    log "ERROR: Restore directory $RESTORE_DIR is not readable"
    exit 1
  fi
}

# -----------------------------------------------------------------------------
# AVOID PARALLEL EXECUTION
# -----------------------------------------------------------------------------
acquire_lockfile() {
  if [ -e "$LOCKFILE" ]; then
    log "Restore already running, exiting"
    exit 0
  fi
  trap 'rm -f "$LOCKFILE"' EXIT
  touch "$LOCKFILE"
}

# -----------------------------------------------------------------------------
# CHECK IF MARIADB IS STILL REACHABLE – ABORT IF YES
# -----------------------------------------------------------------------------
check_mariadb_not_running() {
  log "Checking if MariaDB is reachable at $MYSQL_DB_HOST..."
  if mysql --host="$MYSQL_DB_HOST" --user=root --password="$(< "$MYSQL_ROOT_PASSWORD_FILE")" -e "SELECT 1;" 2>/dev/null; then
    log "ERROR: MariaDB is still reachable at $MYSQL_DB_HOST. Stop it before restoring!"
    exit 1
  else
    log "MariaDB is not reachable. Proceeding with restore."
  fi
}

# -----------------------------------------------------------------------------
# PREPARE BACKUP FILES
# -----------------------------------------------------------------------------
load_backup_files() {
  mapfile -t BACKUP_FILES < <(find "$RESTORE_DIR" -type f -name 'backup-*.sql.gz' | sort)
  if [ "${#BACKUP_FILES[@]}" -eq 0 ]; then
    log "No backup files found in $RESTORE_DIR, exiting"
    exit 0
  fi
}

# -----------------------------------------------------------------------------
# CREATE TEMP MYSQL CONFIG FILE WITH PASSWORD
# -----------------------------------------------------------------------------
create_mysql_config() {
  MYSQL_CNF=$(mktemp)
  chmod 600 "$MYSQL_CNF"
  cat > "$MYSQL_CNF" <<EOF
[client]
host=$MYSQL_DB_HOST
user=$MYSQL_USER
password=$(< "$MYSQL_PASSWORD_FILE")
EOF
}

# -----------------------------------------------------------------------------
# DROP AND RECREATE TARGET DATABASE
# -----------------------------------------------------------------------------
reset_database() {
  log "Dropping and recreating database '$MYSQL_DATABASE'"
  mysql --defaults-extra-file="$MYSQL_CNF" -e "DROP DATABASE IF EXISTS \`$MYSQL_DATABASE\`;"
  mysql --defaults-extra-file="$MYSQL_CNF" -e "CREATE DATABASE \`$MYSQL_DATABASE\`;"
}

# -----------------------------------------------------------------------------
# RESTORE ALL BACKUP FILES
# -----------------------------------------------------------------------------
perform_restore() {
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
}

# -----------------------------------------------------------------------------
# CLEANUP TEMP FILE
# -----------------------------------------------------------------------------
cleanup_mysql_config() {
  rm -f "$MYSQL_CNF"
}

# -----------------------------------------------------------------------------
# MAIN EXECUTION
# -----------------------------------------------------------------------------
main() {
  log "========== Starting restore =========="
  prepare_restore_dir
  acquire_lockfile
  check_mariadb_not_running
  load_backup_files
  create_mysql_config
  reset_database
  perform_restore
  cleanup_mysql_config
  log "========== Restore completed successfully =========="
}

main "$@"