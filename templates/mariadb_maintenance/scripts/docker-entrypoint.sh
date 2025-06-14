#!/bin/bash
set -euo pipefail
umask 077

MYSQL_ROOT_USER="${MYSQL_ROOT_USER:-root}"
MYSQL_ROOT_PASSWORD_FILE="${MYSQL_ROOT_PASSWORD_FILE:?MYSQL_ROOT_PASSWORD_FILE is required}"
MYSQL_DB_HOST="${MYSQL_DB_HOST:-mariadb}"
MYSQL_RESTORE_DRY_RUN="${MYSQL_RESTORE_DRY_RUN:-false}"

RESTORE_DIR="${RESTORE_DIR:-/restore}"
LOCK_FILE="/tmp/restore.lock"

cleanup() {
  [[ -f "$LOCK_FILE" ]] && rm -f "$LOCK_FILE"
}
trap cleanup EXIT INT TERM

is_db_running() {
  if mariadb-admin ping --silent --host="$MYSQL_DB_HOST" --user="$MYSQL_ROOT_USER" --password="$(<"$MYSQL_ROOT_PASSWORD_FILE")" > /dev/null 2>&1; then
    echo "[FATAL] MariaDB appears to be running (ping successful). Aborting restore."
    exit 1
  fi

  if pgrep -x mariadbd > /dev/null; then
    echo "[FATAL] MariaDB process found running. Aborting restore."
    exit 1
  fi
}

get_restore_chain() {
  local full_dir
  full_dir="$(find "$RESTORE_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | grep -E '^[0-9]{8}_[0-9]{2}$' | sort | head -n1 || true)"
  if [[ -z "$full_dir" ]]; then
    echo "[FATAL] No full backup found in $RESTORE_DIR"
    exit 1
  fi

  local chain=("$full_dir")
  local next_idx=1
  while :; do
    local inc_dir="${full_dir}_$(printf '%02d' $next_idx)"
    if [[ -d "$RESTORE_DIR/$inc_dir" ]]; then
      chain+=("$inc_dir")
      ((next_idx++))
    else
      break
    fi
  done

  # Check for gaps
  for ((i=1; i<${#chain[@]}; i++)); do
    local expected="${full_dir}_$(printf '%02d' $i)"
    if [[ "${chain[$i]}" != "$expected" ]]; then
      echo "[FATAL] Backup chain inconsistent. Expected $expected, found ${chain[$i]}"
      exit 1
    fi
  done

  printf "%s\n" "${chain[@]}"
}

decompress_if_needed() {
  local dir="$1"
  if find "$dir" -type f -name '*.qp' | grep -q .; then
    echo "[INFO] Decompressing backup directory: $dir"
    mariadb-backup --decompress --target-dir="$dir"
  else
    echo "[INFO] No compressed files found in $dir"
  fi
}

prepare_restore_chain() {
  local chain=("$@")
  local full_path="$RESTORE_DIR/${chain[0]}"

  decompress_if_needed "$full_path"
  echo "[INFO] Preparing FULL backup: $full_path"
  mariadb-backup --prepare --target-dir="$full_path"

  for ((i=1; i<${#chain[@]}; i++)); do
    local inc_path="$RESTORE_DIR/${chain[$i]}"
    decompress_if_needed "$inc_path"
    echo "[INFO] Preparing INCREMENTAL backup: $inc_path"
    mariadb-backup --prepare --target-dir="$full_path" --incremental-dir="$inc_path"
  done

  echo "$full_path"
}

perform_restore() {
  echo "[INFO] Starting automated restore from $RESTORE_DIR"
  local chain
  mapfile -t chain < <(get_restore_chain)
  local ready_dir
  ready_dir="$(prepare_restore_chain "${chain[@]}")"

  if [[ "$MYSQL_RESTORE_DRY_RUN" == "true" ]]; then
    echo "[INFO] MYSQL_RESTORE_DRY_RUN is enabled. No copy-back performed."
    return
  fi

  rm -rf /var/lib/mysql/*
  echo "[INFO] Deleted old database files in /var/lib/mysql"

  mariadb-backup --copy-back --target-dir="$ready_dir"

  sync
  chown -R mysql:mysql /var/lib/mysql
  echo "[INFO] Changed ownership of /var/lib/mysql to mysql:mysql"
  echo "[INFO] Restore completed successfully."
}

main() {
  if [[ -d "$RESTORE_DIR" ]] && [[ "$(ls -A "$RESTORE_DIR")" ]]; then
    echo "[INFO] Restore requested. MariaDB MUST NOT be running during restore."

    if [[ -f "$LOCK_FILE" ]]; then
      echo "[WARN] Restore lockfile found. Skipping restore to avoid duplicate restore."
    else
      is_db_running
      touch "$LOCK_FILE"
      perform_restore
    fi
  else
    echo "[INFO] No restore requested. Proceeding to backup schedule."
  fi

  echo "[INFO] Starting supercronic with cron file: $*"
  exec /usr/local/bin/supercronic "$@"
}

main "/usr/local/bin/backup.cron"