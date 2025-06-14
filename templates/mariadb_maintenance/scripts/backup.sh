#!/bin/bash
set -euo pipefail
umask 077

MYSQL_ROOT_USER="${MYSQL_ROOT_USER:-root}"
MYSQL_DATABASE="${MYSQL_DATABASE:?MYSQL_DATABASE is required}"
MYSQL_ROOT_PASSWORD_FILE="${MYSQL_ROOT_PASSWORD_FILE:?MYSQL_ROOT_PASSWORD_FILE is required}"
MYSQL_DB_HOST="${MYSQL_DB_HOST:-mariadb}"
MYSQL_BACKUP_RETENTION_DAYS="${MYSQL_BACKUP_RETENTION_DAYS:-7}"
MYSQL_BACKUP_COMPRESS_THREADS="${MYSQL_BACKUP_COMPRESS_THREADS:-4}"
MYSQL_BACKUP_PARALLEL="${MYSQL_BACKUP_PARALLEL:-4}"
MYSQL_BACKUP_MIN_FREE_MB="${MYSQL_BACKUP_MIN_FREE_MB:-10240}"

BACKUP_DIR="${BACKUP_DIR:-/backup}"
LOCK_FILE="/tmp/backup.lock"
BACKUP_TYPE="${1:-full}"

TODAY="$(date +'%Y%m%d')"
TARGET_DIR=""

cleanup() {
  if [[ -f "$LOCK_FILE" ]]; then
    rm -f "$LOCK_FILE" || echo "[WARN] Could not remove lock file"
  fi
}
trap cleanup EXIT INT TERM

is_db_running() {
  mariadb-admin ping --silent --host="$MYSQL_DB_HOST" --user="$MYSQL_ROOT_USER" --password="$(<"$MYSQL_ROOT_PASSWORD_FILE")" > /dev/null 2>&1
}

check_free_space() {
  local free_mb
  free_mb=$(df --output=avail -m "$BACKUP_DIR" | tail -n1 | awk '{print $1}')
  if [[ "$free_mb" -lt "$MYSQL_BACKUP_MIN_FREE_MB" ]]; then
    echo "[FATAL] Not enough free space: ${free_mb}MB available, ${MYSQL_BACKUP_MIN_FREE_MB}MB required."
    exit 1
  fi
}

remove_old_backups() {
  echo "[INFO] Checking for recent full backups (safety check)"

  local recent_full_count=0

  if [[ -d "$BACKUP_DIR/full" ]]; then
    recent_full_count=$(find "$BACKUP_DIR/full" -mindepth 1 -maxdepth 1 -type d -mtime -"${MYSQL_BACKUP_RETENTION_DAYS}" | wc -l)
  else
    echo "[WARN] No full backup directory found; assuming no recent full backups exist."
  fi

  if [[ "$recent_full_count" -eq 0 ]]; then
    echo "[WARN] No recent full backup found (within last ${MYSQL_BACKUP_RETENTION_DAYS} days)."
    echo "[INFO] Aborting old backup cleanup to avoid data loss risk."
    return 0
  fi

  echo "[INFO] Removing backups older than $MYSQL_BACKUP_RETENTION_DAYS days"

  if [[ -d "$BACKUP_DIR/full" ]]; then
    find "$BACKUP_DIR/full" -mindepth 1 -maxdepth 1 -type d -mtime +"$MYSQL_BACKUP_RETENTION_DAYS" -exec rm -rf {} +
  else
    echo "[INFO] No full backup directory found; skipping old full backups."
  fi

  if [[ -d "$BACKUP_DIR/incremental" ]]; then
    find "$BACKUP_DIR/incremental" -mindepth 1 -maxdepth 1 -type d -mtime +"$MYSQL_BACKUP_RETENTION_DAYS" -exec rm -rf {} +
  else
    echo "[INFO] No incremental backup directory found; skipping old incremental backups."
  fi

  if [[ -d "$BACKUP_DIR/dumps" ]]; then
    find "$BACKUP_DIR/dumps" -mindepth 1 -maxdepth 1 -type f -mtime +"$MYSQL_BACKUP_RETENTION_DAYS" -exec rm -f {} +
  else
    echo "[INFO] No dumps directory found; skipping old dump removal."
  fi
}

verify_backup() {
  echo "[INFO] Verifying $TARGET_DIR"
  mariadb-backup --prepare --target-dir="$TARGET_DIR" --read-only
}

next_full_dir() {
  local count
  count=$(find "$BACKUP_DIR/full" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | grep "^$TODAY" | wc -l)
  printf "%s_%02d" "$TODAY" $((count + 1))
}

next_inc_dir() {
  local base="$1"
  local count
  count=$(find "$BACKUP_DIR/incremental" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | grep "^${base}_" | wc -l)
  printf "%s_%02d" "$base" $((count + 1))
}

perform_full_backup() {
  local dir_name
  dir_name="$(next_full_dir)"
  TARGET_DIR="$BACKUP_DIR/full/$dir_name"
  mkdir -p "$TARGET_DIR"
  echo "[INFO] FULL backup -> $TARGET_DIR"

  mariadb-backup \
    --backup \
    --target-dir="$TARGET_DIR" \
    --host="$MYSQL_DB_HOST" \
    --user="$MYSQL_ROOT_USER" \
    --password="$(<"$MYSQL_ROOT_PASSWORD_FILE")" \
    --compress \
    --compress-threads="$MYSQL_BACKUP_COMPRESS_THREADS" \
    --parallel="$MYSQL_BACKUP_PARALLEL"

  verify_backup
}

perform_incremental_backup() {
  local base_name
  base_name=$(find "$BACKUP_DIR/full" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort | tail -n1 || true)

  if [[ -z "$base_name" ]]; then
    echo "[WARN] No full backup found, creating full backup instead."
    perform_full_backup
    return
  fi

  local base_dir="$BACKUP_DIR/full/$base_name"
  local last_inc_dir
  last_inc_dir=$(find "$BACKUP_DIR/incremental" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | grep "^$base_name" | sort | tail -n1 || true)

  [[ -n "$last_inc_dir" ]] && base_dir="$BACKUP_DIR/incremental/$last_inc_dir"

  local inc_name
  inc_name="$(next_inc_dir "$base_name")"
  TARGET_DIR="$BACKUP_DIR/incremental/$inc_name"
  mkdir -p "$TARGET_DIR"
  echo "[INFO] INCREMENTAL backup -> $TARGET_DIR (base: $base_dir)"

  mariadb-backup \
    --backup \
    --target-dir="$TARGET_DIR" \
    --incremental-basedir="$base_dir" \
    --host="$MYSQL_DB_HOST" \
    --user="$MYSQL_ROOT_USER" \
    --password="$(<"$MYSQL_ROOT_PASSWORD_FILE")" \
    --compress \
    --compress-threads="$MYSQL_BACKUP_COMPRESS_THREADS" \
    --parallel="$MYSQL_BACKUP_PARALLEL"

  verify_backup
}

perform_dump_backup() {
  local dump_file="$BACKUP_DIR/dumps/mariadb_dump_${TODAY}_$(date +'%H%M%S').sql.gz"
  mkdir -p "$BACKUP_DIR/dumps"
  echo "[INFO] DUMP backup -> $dump_file"

  mariadb-dump \
    --host="$MYSQL_DB_HOST" \
    --user="$MYSQL_ROOT_USER" \
    --password="$(<"$MYSQL_ROOT_PASSWORD_FILE")" \
    --databases "$MYSQL_DATABASE" \
    --single-transaction \
    --routines \
    --triggers \
    --set-gtid-purged=OFF \
  | gzip -9 > "$dump_file"

  echo "[INFO] Dump completed: $dump_file"
}

main() {
  [[ -f "$LOCK_FILE" ]] && { echo "[WARN] Lockfile found, skipping."; exit 0; }
  touch "$LOCK_FILE"

  is_db_running || { echo "[FATAL] DB not running"; exit 1; }

  check_free_space
  remove_old_backups

  case "$BACKUP_TYPE" in
    full)
      perform_full_backup
      ;;
    incremental)
      perform_incremental_backup
      ;;
    dump)
      perform_dump_backup
      ;;
    *)
      echo "[FATAL] Invalid backup type: $BACKUP_TYPE"
      exit 1
      ;;
  esac
}

main "$@"