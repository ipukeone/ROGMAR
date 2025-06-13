#!/bin/bash
set -euo pipefail
umask 077

BACKUP_DIR="${BACKUP_DIR:-/backup}"
MYSQL_ROOT_PW_FILE="${MYSQL_ROOT_PASSWORD_FILE:?MYSQL_ROOT_PASSWORD_FILE is required}"
LOCK_FILE="/tmp/backup.lock"
MYSQL_BACKUP_RETENTION_DAYS="${MYSQL_BACKUP_RETENTION_DAYS:-7}"

BACKUP_TYPE="${1:-full}"

TIMESTAMP="$(date +'%Y%m%d_%H%M%S')"
TARGET_DIR="$BACKUP_DIR/$BACKUP_TYPE/$TIMESTAMP"

cleanup() {
  if [[ -f "$LOCK_FILE" ]]; then
    echo "[INFO] Cleaning up: removing lockfile."
    rm -f "$LOCK_FILE"
  fi
}
trap cleanup EXIT INT TERM

is_db_running() {
  local MYSQL_ROOT_PW
  MYSQL_ROOT_PW="$(<"$MYSQL_ROOT_PW_FILE")"

  if ! mysqladmin ping --silent --host=127.0.0.1 --user=root --password="$MYSQL_ROOT_PW" > /dev/null 2>&1; then
    echo "[ERROR] MariaDB is NOT running. Backup requires running DB."
    return 1
  fi
  return 0
}

remove_old_backups() {
  echo "[INFO] Removing backups older than $MYSQL_BACKUP_RETENTION_DAYS days in $BACKUP_DIR"
  find "$BACKUP_DIR" -mindepth 2 -maxdepth 2 -type d -mtime +"$MYSQL_BACKUP_RETENTION_DAYS" -exec rm -rf {} +
}

perform_full_backup() {
  echo "[INFO] Starting FULL backup at $TARGET_DIR"
  mkdir -p "$TARGET_DIR"

  mariabackup --backup --target-dir="$TARGET_DIR" --user=root --password="$(<"$MYSQL_ROOT_PW_FILE")"
  if [[ $? -ne 0 ]]; then
    echo "[ERROR] mariabackup --backup failed"
    exit 1
  fi

  echo "[INFO] FULL backup completed successfully"
}

perform_incremental_backup() {
  echo "[INFO] Starting INCREMENTAL backup at $TARGET_DIR"

  local last_full_backup
  last_full_backup=$(find "$BACKUP_DIR/full" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1 || true)

  if [[ -z "$last_full_backup" ]]; then
    echo "[WARN] No full backup found. Performing full backup instead."
    perform_full_backup
    return
  fi

  local last_inc_backup
  last_inc_backup=$(find "$BACKUP_DIR/incremental" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1 || true)

  local base_dir
  if [[ -z "$last_inc_backup" ]]; then
    base_dir="$last_full_backup"
  else
    base_dir="$last_inc_backup"
  fi

  mkdir -p "$TARGET_DIR"

  mariabackup --backup --target-dir="$TARGET_DIR" --incremental-basedir="$base_dir" --user=root --password="$(<"$MYSQL_ROOT_PW_FILE")"
  if [[ $? -ne 0 ]]; then
    echo "[ERROR] mariabackup --incremental backup failed"
    exit 1
  fi

  echo "[INFO] INCREMENTAL backup completed successfully"
}

main() {
  if [[ -f "$LOCK_FILE" ]]; then
    echo "[WARN] Backup lockfile found. Skipping backup to avoid concurrent runs."
    exit 0
  fi

  if ! is_db_running; then
    echo "[FATAL] Backup aborted: MariaDB is not running."
    exit 1
  fi

  touch "$LOCK_FILE"

  remove_old_backups

  case "$BACKUP_TYPE" in
    full)
      perform_full_backup
      ;;
    incremental)
      perform_incremental_backup
      ;;
    *)
      echo "[FATAL] Invalid backup type: $BACKUP_TYPE. Allowed: full, incremental."
      exit 1
      ;;
  esac
}

main "$@"