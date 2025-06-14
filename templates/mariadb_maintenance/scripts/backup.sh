#!/bin/bash
set -euo pipefail
umask 077

MYSQL_ROOT_USER="${MYSQL_ROOT_USER:-root}"
MYSQL_ROOT_PW_FILE="${MYSQL_ROOT_PASSWORD_FILE:?MYSQL_ROOT_PASSWORD_FILE is required}"
MYSQL_DB_HOST="${MYSQL_DB_HOST:-mariadb}"
MYSQL_BACKUP_RETENTION_DAYS="${MYSQL_BACKUP_RETENTION_DAYS:-7}"
MYSQL_COMPRESS_THREADS="${MYSQL_COMPRESS_THREADS:-4}"
MYSQL_PARALLEL="${MYSQL_PARALLEL:-4}"

BACKUP_DIR="${BACKUP_DIR:-/backup}"
LOCK_FILE="/tmp/backup.lock"

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

  if ! mariadb-admin ping --silent --host="$MYSQL_DB_HOST" --user="$MYSQL_ROOT_USER" --password="$MYSQL_ROOT_PW" > /dev/null 2>&1; then
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

  mariadb-backup --backup --target-dir="$TARGET_DIR" --host="$MYSQL_DB_HOST" --user="$MYSQL_ROOT_USER" --password="$(<"$MYSQL_ROOT_PW_FILE")" --compress --compress-threads="$MYSQL_COMPRESS_THREADS" --parallel="$MYSQL_PARALLEL"
  if [[ $? -ne 0 ]]; then
    echo "[ERROR] mariadb-backup --backup failed"
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
  
  mariadb-backup --backup --target-dir="$TARGET_DIR" --incremental-basedir="$base_dir" --host="$MYSQL_DB_HOST" --user="$MYSQL_ROOT_USER" --password="$(<"$MYSQL_ROOT_PW_FILE")" --compress --compress-threads="$MYSQL_COMPRESS_THREADS" --parallel="$MYSQL_PARALLEL"
  if [[ $? -ne 0 ]]; then
    echo "[ERROR] mariadb-backup --incremental backup failed"
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