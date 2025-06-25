#!/bin/bash
set -euo pipefail
umask 077

RESTORE_DIR="/restore"
TMP_BASE="/tmp/restore_chain"
MARIADB_DIR="/var/lib/mysql"
DRY_RUN="${MARIADB_RESTORE_DRY_RUN:-false}"
DEBUG="${MARIADB_RESTORE_DEBUG:-false}"
LOCKFILE="/tmp/restore.lock"

# === LOGGING === #
log_info()  { echo "[INFO] $*"; }
log_debug() { [[ "$DEBUG" == "true" ]] && echo "[DEBUG] $*"; }
log_dry()   { [[ "$DRY_RUN" == "true" ]] && echo "[DRY RUN] $*"; }
log_err()   { echo "[ERROR] $*" >&2; exit 1; }

# === CLEANUP ON EXIT === #
cleanup() {
  rm -rf "$TMP_BASE"
  rm -f "$LOCKFILE"
}
trap cleanup EXIT INT TERM

# === FIND BACKUP CHAIN === #
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

fix_backup_cnf() {
  local dir="$1"
  local f="$dir/backup-my.cnf"
  [[ ! -f "$f" ]] && return
  sed -i 's|^datadir=.*|datadir=/var/lib/mysql|' "$f"
  sed -i 's|^innodb_data_home_dir=.*|innodb_data_home_dir=/var/lib/mysql|' "$f"
  sed -i 's|^innodb_log_group_home_dir=.*|innodb_log_group_home_dir=/var/lib/mysql|' "$f"
}

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

copy_back() {
  if [[ "$DRY_RUN" == "true" ]]; then
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

cleanup_restore_dir() {
  log_info "Cleaning up restore temp data"
  rm -rf "$TMP_BASE"
  rm -rf "$RESTORE_DIR"/*
}

test_fs_writable() {
  local testfile="/var/lib/mysql/.writetest_$$"
  if touch "$testfile" 2>/dev/null; then
    rm -f "$testfile"
    return 0
  else
    return 1
  fi
}

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

    find_restore_chain
    prepare_chain "${RESTORE_CHAIN[@]}"
    copy_back
    cleanup_restore_dir
    log_info "Restore completed."
  else
    log_info "No restore requested. Proceeding to backup schedule."
  fi

  log_info "Starting supercronic with cron file: $cron_file"
  exec /usr/local/bin/supercronic "$cron_file"
}

main "/usr/local/bin/backup.cron"