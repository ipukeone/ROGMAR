#!/bin/bash
set -euo pipefail
umask 077

RESTORE_DIR="${RESTORE_DIR:-/restore}"
LOCK_FILE="/tmp/restore.lock"
MYSQL_ROOT_PW_FILE="${MYSQL_ROOT_PASSWORD_FILE:?MYSQL_ROOT_PASSWORD_FILE is required}"

cleanup() {
  if [[ -f "$LOCK_FILE" ]]; then
    echo "[INFO] Cleaning up: removing lockfile."
    rm -f "$LOCK_FILE"
  fi
}
trap cleanup EXIT INT TERM

is_db_running() {
  if [[ ! -f "$MYSQL_ROOT_PW_FILE" ]]; then
    echo "[FATAL] MYSQL_ROOT_PASSWORD secret file not found at $MYSQL_ROOT_PW_FILE"
    exit 1
  fi

  local MYSQL_ROOT_PW
  MYSQL_ROOT_PW="$(<"$MYSQL_ROOT_PW_FILE")"

  if mysqladmin ping --silent --host=127.0.0.1 --user=root --password="$MYSQL_ROOT_PW" > /dev/null 2>&1; then
    echo "[ERROR] MariaDB appears to be running (ping successful). Aborting restore."
    return 0
  fi

  if pgrep -x mariadbd > /dev/null; then
    echo "[ERROR] MariaDB process found running. Aborting restore."
    return 0
  fi

  return 1
}

perform_restore() {
  echo "[INFO] Starting restore from $RESTORE_DIR"

  mariabackup --prepare --target-dir="$RESTORE_DIR"
  if [[ $? -ne 0 ]]; then
    echo "[ERROR] mariabackup --prepare failed"
    exit 1
  fi

  rm -rf /var/lib/mysql/*
  echo "[INFO] Deleted old database files in /var/lib/mysql"

  mariabackup --copy-back --target-dir="$RESTORE_DIR"
  if [[ $? -ne 0 ]]; then
    echo "[ERROR] mariabackup --copy-back failed"
    exit 1
  fi

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
      if is_db_running; then
        echo "[FATAL] Restore aborted: MariaDB is running. Stop the database before restoring."
        exit 1
      fi

      touch "$LOCK_FILE"
      perform_restore
    fi
  else
    echo "[INFO] No restore requested. Proceeding to backup schedule."
  fi

  exec /usr/local/bin/supercronic "$@"
}

main "$@"