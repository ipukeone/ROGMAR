#!/bin/bash
set -euo pipefail
umask 077

# === ENVIRONMENT VARIABLES === #
MYSQL_ROOT_USER="${MYSQL_ROOT_USER:-root}"
MYSQL_DATABASE="${MYSQL_DATABASE:?MYSQL_DATABASE is required}"
MYSQL_ROOT_PASSWORD_FILE="${MYSQL_ROOT_PASSWORD_FILE:?MYSQL_ROOT_PASSWORD_FILE is required}"
MYSQL_DB_HOST="${MYSQL_DB_HOST:-mariadb}"
MYSQL_BACKUP_RETENTION_DAYS="${MYSQL_BACKUP_RETENTION_DAYS:-7}"

BACKUP_DIR="/backup"
TMP_DIR="/tmp/mariadb_backup"
TODAY="$(date +'%Y%m%d')"
DEBUG="${MYSQL_BACKUP_DEBUG:-true}"

# === LOGGING === #
log_info()    { echo "[INFO] $*"; }
log_debug()   { [[ "$DEBUG" == "true" ]] && echo "[DEBUG] $*"; }
log_error()   { echo "[ERROR] $*" >&2; }

# === CLEANUP TEMP DIR ON EXIT === #
trap 'rm -rf "$TMP_DIR"; rm -f "$LOCKFILE"' EXIT

# === LOCKFILE === #
LOCKFILE="/tmp/mariadb_backup.lock"

if [[ -e "$LOCKFILE" ]]; then
  echo "[ERROR] Another backup process is already running. Lockfile exists: $LOCKFILE"
  exit 1
fi

echo "$$" > "$LOCKFILE"

# === FUNCTION: Ensure directory exists and is empty === #
prepare_tmp_dir() {
  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"

  log_debug "Created $TMP_DIR"
}

# === FUNCTION: Compress entire folder to .zst with proper naming === #
compress_backup() {
  local type="$1"     # full|incremental|dump
  local suffix="$2"   # e.g., 01 or 01_01
  local source_dir="${3:-$TMP_DIR}"  # optional: directory to be compressed

  mkdir -p "$BACKUP_DIR/$TODAY"

  local file_name
  if [[ "$type" == "dump" ]]; then
    file_name="${type}_${TODAY}_${suffix}.sql.zst"
  else
    file_name="${type}_${TODAY}_${suffix}.zst"
  fi

  log_info "Compressing backup -> $file_name"

  tar -cf - -C "$source_dir" . | zstd --rm -q --content-size -o "$BACKUP_DIR/$TODAY/$file_name" || {
    log_error "Failed to compress backup"
    exit 1
  }

  log_info "Backup saved as $BACKUP_DIR/$TODAY/$file_name"
}

# === FUNCTION: Get latest full backup for incremental usage === #
get_latest_full() {
  local latest_full
  latest_full=$(find "$BACKUP_DIR"/"$TODAY"/full_"$TODAY"_*.zst "$BACKUP_DIR"/full_"$TODAY"_*.zst 2>/dev/null \
    | grep -v '.zst.*.zst' | sort | tail -n1)

  if [[ -z "$latest_full" ]]; then
    latest_full=$(find "$BACKUP_DIR"/*/full_${TODAY}_*.zst "$BACKUP_DIR"/full_${TODAY}_*.zst 2>/dev/null \
      | grep -v '.zst.*.zst' | sort | tail -n1)
  fi

  echo "$latest_full"
}

# === FUNCTION: Decompress a .zst backup into /tmp === #
decompress_backup() {
  local file="$1"

  log_info "Decompressing $file -> /tmp/mariadb_backup/"

  prepare_tmp_dir

  zstd -d -q --stdout "$file" | tar -xf - -C "$TMP_DIR" || {
    log_error "Failed to decompress $file"
    exit 1
  }
}

# === FUNCTION: Create full backup in /tmp first, then compress === #
perform_full_backup() {
  prepare_tmp_dir

  log_info "Creating FULL backup in $TMP_DIR"

  mariadb-backup \
    --backup \
    --target-dir="$TMP_DIR" \
    --host="$MYSQL_DB_HOST" \
    --user="$MYSQL_ROOT_USER" \
    --password="$(cat "$MYSQL_ROOT_PASSWORD_FILE")" > /dev/null 2>&1 || {
    log_error "MariaDB full backup failed"
    exit 1
  }

  log_info "Full backup created in $TMP_DIR"

  # Count existing full backups today
  local count=0
  if [[ -d "$BACKUP_DIR/$TODAY" ]]; then
    log_debug "Counting existing full backups from today in $BACKUP_DIR/$TODAY"
    count=$(find "$BACKUP_DIR"/"$TODAY" -type f -name "full_${TODAY}_*.zst" | wc -l)
  else
    log_debug "No existing full backups from today in $BACKUP_DIR/$TODAY"
  fi

  local suffix=$(printf "%02d" $((count + 1)))
  compress_backup "full" "$suffix" "$TMP_DIR"
}

# === FUNCTION: Create incremental backup based on latest full backup === #
perform_incremental_backup() {
  local latest_full
  latest_full=$(get_latest_full)

  if [[ ! -f "$latest_full" ]]; then
    log_info "No full backup found. Creating one instead."
    perform_full_backup
    return
  fi

  log_info "Using $latest_full as base for incremental"

  # Decompress latest full backup into /tmp
  decompress_backup "$latest_full"

  # Extract full backup number
  local full_number="${latest_full##*_}"  # e.g., full_20250615_01.zst -> 01.zst
  full_number="${full_number%.zst}"      # 01.zst -> 01

  # Count existing incrementals for this full backup
  local inc_count
  inc_count=$(find "$BACKUP_DIR"/"$TODAY" -type f -name "incremental_${TODAY}_${full_number}_*.zst" | wc -l)

  local inc_suffix=$(printf "%02d" $((inc_count + 1)))

  log_info "Creating INCREMENTAL backup -> incremental_${TODAY}_${full_number}_${inc_suffix}.zst"

  mariadb-backup \
    --backup \
    --target-dir="$TMP_DIR/incremental" \
    --incremental-basedir="$TMP_DIR" \
    --host="$MYSQL_DB_HOST" \
    --user="$MYSQL_ROOT_USER" \
    --password="$(cat "$MYSQL_ROOT_PASSWORD_FILE")" > /dev/null 2>&1 || {
    log_error "Failed to create incremental backup"
    exit 1
  }

  compress_backup "incremental" "${full_number}_${inc_suffix}" "$TMP_DIR/incremental"
}

# === FUNCTION: Create SQL dump backup using ZSTD === #
perform_dump_backup() {
  prepare_tmp_dir

  local dump_file="$TMP_DIR/dump.sql"
  local compressed_file="dump_${TODAY}_$(date +'%H%M%S').sql.zst"

  log_info "Performing DUMP backup -> $compressed_file"

  mariadb-dump \
    --host="$MYSQL_DB_HOST" \
    --user="$MYSQL_ROOT_USER" \
    --password="$(cat "$MYSQL_ROOT_PASSWORD_FILE")" \
    --databases "$MYSQL_DATABASE" \
    --single-transaction \
    --routines \
    --triggers \
    --events \
    --add-drop-database \
    --add-drop-table \
    --create-options \
    --extended-insert \
    --quick \
    --net_buffer_length=1M \
    > "$dump_file" 2>/dev/null || {
      log_error "Failed to create SQL dump"
      exit 1
    }

  compress_backup "dump" "$(date +'%H%M%S')" "$TMP_DIR"
}

# === FUNCTION: Remove backup folders older than X days === #
remove_old_backups() {
  log_info "Checking for backup folders older than $MYSQL_BACKUP_RETENTION_DAYS days"

  local old_dirs
  mapfile -t old_dirs < <(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +"$MYSQL_BACKUP_RETENTION_DAYS")

  local count="${#old_dirs[@]}"

  if (( count == 0 )); then
    log_info "No old backup folders found to remove."
    return
  fi

  log_info "Found $count old backup folder(s) to delete:"
  for dir in "${old_dirs[@]}"; do
    log_info "  -> $dir"
    rm -rf "$dir"
  done

  log_debug "$count backup folder(s) older than $MYSQL_BACKUP_RETENTION_DAYS days removed."
}

# === MAIN FUNCTION === #
main() {
  # Filter output unless DEBUG=true
  if [[ "$DEBUG" != "true" ]]; then
    exec > >(grep -E '^\[INFO\] |^\[ERROR\] ') 2>&1
  fi

  remove_old_backups

  case "$1" in
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
      log_error "Invalid backup type: $1"
      exit 1
      ;;
  esac
}

main "$@"