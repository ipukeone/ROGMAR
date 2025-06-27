#!/bin/bash
set -euo pipefail
umask 077

# === ENVIRONMENT VARIABLES === #
MARIADB_ROOT_USER="${MARIADB_ROOT_USER:-root}"
MARIADB_ROOT_PASSWORD_FILE="${MARIADB_ROOT_PASSWORD_FILE:?MARIADB_ROOT_PASSWORD_FILE is required}"
MARIADB_DB_HOST="${MARIADB_DB_HOST:-mariadb}"
MARIADB_RESTORE_DRY_RUN="${MARIADB_RESTORE_DRY_RUN:-false}"

RESTORE_DIR="/restore"
TMP_BASE="/tmp/restore_chain"
MARIADB_DIR="/var/lib/mysql"
DEBUG="${MARIADB_RESTORE_DEBUG:-false}"
LOCKFILE="/tmp/restore.lock"

# === LOGGING === #
log_info() {
  printf '[INFO] %s\n' "$*"
}

log_debug() {
  if [[ "${DEBUG:-false}" == "true" ]]; then
    printf '[DEBUG] %s\n' "$*"
  fi
}

log_dry() {
  if [[ "${MARIADB_RESTORE_DRY_RUN:-false}" == "true" ]]; then
    printf '[DRY RUN] %s\n' "$*"
  fi
}

log_err() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

# === CLEANUP ON EXIT === #
# Removes temporary restore data and lockfile when the script exits
cleanup() {
  rm -rf "$TMP_BASE"
  rm -f "$LOCKFILE"
}
trap cleanup EXIT INT TERM

# === CHECK IF DB IS RUNNING === #
# Verifies that MariaDB is not running before starting the restore
is_db_running() {
  if mariadb-admin ping --silent --host="$MARIADB_DB_HOST" --user="$MARIADB_ROOT_USER" --password="$(<"$MARIADB_ROOT_PASSWORD_FILE")" > /dev/null 2>&1; then
    log_err "MariaDB appears to be running (ping successful). Aborting restore."
  fi

  if pgrep -x mariadbd > /dev/null; then
    log_err "MariaDB process found running. Aborting restore."
  fi
}

# === FIND BACKUP CHAIN === #
# Identifies the latest full backup and associated incrementals
find_restore_chain() {
  local full
  full=$(find "$RESTORE_DIR" -maxdepth 1 -type f -name 'full_*.zst' | sort -V | tail -n1)
  [[ -z "$full" ]] && log_err "No full backup found."

  local id="${full##*/}"
  id="${id#full_}"
  id="${id%.zst}"

  log_info "Detected backup ID: $id"

  mapfile -t RESTORE_CHAIN < <(find "$RESTORE_DIR" -maxdepth 1 -type f -name "incremental_${id}_*.zst" | sort -V)
  RESTORE_CHAIN=("$full" "${RESTORE_CHAIN[@]}")

  log_info "Restore chain to be applied:"
  for f in "${RESTORE_CHAIN[@]}"; do
    log_info " - $(basename "$f")"
  done
}

# === FIX BACKUP CONFIG FILE === #
# Adjusts backup-my.cnf to point to correct data directory
fix_backup_cnf() {
  local dir="$1"
  local f="$dir/backup-my.cnf"
  [[ ! -f "$f" ]] && return
  sed -i 's|^datadir=.*|datadir=/var/lib/mysql|' "$f"
  sed -i 's|^innodb_data_home_dir=.*|innodb_data_home_dir=/var/lib/mysql|' "$f"
  sed -i 's|^innodb_log_group_home_dir=.*|innodb_log_group_home_dir=/var/lib/mysql|' "$f"
}

# === PREPARE CHAIN === #
# Decompresses and prepares full and incremental backups
prepare_chain() {
  rm -rf "$TMP_BASE"
  mkdir -p "$TMP_BASE/full"

  local restore_files=("$@")
  local first=1

  for archive in "${restore_files[@]}"; do
    local name=$(basename "${archive%.zst}")
    local target_dir="$TMP_BASE/$name"
    [[ $first -eq 1 ]] && target_dir="$TMP_BASE/full" && first=0
    mkdir -p "$target_dir"

    log_info "Extracting: $(basename "$archive") → $target_dir"
    zstd -d --stdout "$archive" | tar -xf - -C "$target_dir" || log_err "Extraction failed"
    fix_backup_cnf "$target_dir"
  done

  log_info "Preparing base..."
  mariadb-backup --prepare --target-dir="$TMP_BASE/full"

  for inc in "${restore_files[@]:1}"; do
    local name=$(basename "${inc%.zst}")
    log_info "Applying incremental: $name"
    mariadb-backup --prepare \
      --target-dir="$TMP_BASE/full" \
      --incremental-dir="$TMP_BASE/$name"
  done
}

# === COPY BACK === #
# Replaces MariaDB data directory with the restored data
copy_back() {
  if [[ "$MARIADB_RESTORE_DRY_RUN" == "true" ]]; then
    log_dry "Would wipe $MARIADB_DIR and copy data from $TMP_BASE/full"
    return
  fi

  log_info "Removing $MARIADB_DIR content..."
  find "$MARIADB_DIR" -mindepth 1 -exec rm -rf {} + || log_err "Failed to wipe contents of $MARIADB_DIR"
  chown mysql:mysql "$MARIADB_DIR"

  log_info "Copying data to $MARIADB_DIR..."
  mariadb-backup --copy-back --target-dir="$TMP_BASE/full"
  chown -R mysql:mysql "$MARIADB_DIR"
  sync
}

# === CLEANUP RESTORE DIR === #
# Removes extracted backups and original compressed archives
cleanup_restore_dir() {
  log_info "Cleaning up restore temp data"
  rm -rf "$TMP_BASE"
  rm -rf "$RESTORE_DIR"/*
}

# === TEST FILESYSTEM WRITABILITY === #
# Ensures MariaDB data dir is writable (e.g. not read-only mount)
test_fs_writable() {
  local testfile="/var/lib/mysql/.writetest_$$"
  if touch "$testfile" 2>/dev/null; then
    rm -f "$testfile"
    return 0
  else
    return 1
  fi
}

# === MAIN ENTRY POINT === #
# Executes restore if triggered, otherwise starts cron
main() {
  local cron_file="${1:-/usr/local/bin/backup.cron}"

  if [[ -d "$RESTORE_DIR" && "$(find "$RESTORE_DIR" -maxdepth 1 -name 'full_*.zst' | wc -l)" -gt 0 ]]; then
    if ! ( set -o noclobber; echo "$$" > "$LOCKFILE") 2> /dev/null; then
      log_err "Restore lockfile exists. Another restore might be running or previous restore did not clean up. Aborting."
    fi
    
    log_info "Restore requested. Starting restore..."
    
    if ! test_fs_writable; then
      log_err "/var/lib/mysql is not writable. Check if 'read_only: true' is set in docker-compose.yml. Set it temporary to false for a restore!"
    fi
    
    is_db_running

    find_restore_chain
    prepare_chain "${RESTORE_CHAIN[@]}"
    copy_back
    cleanup_restore_dir
    log_info "Restore completed."
    return 0
  else
    log_info "No restore requested. Proceeding to backup schedule."
  fi

  log_info "Starting supercronic with cron file: $cron_file"
  exec /usr/local/bin/supercronic "$cron_file"
}

main "/usr/local/bin/backup.cron"