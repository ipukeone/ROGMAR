#!/bin/bash
set -euo pipefail
umask 077

# ─────────────────────────────────────────────
# CONFIG – Passe das hier an
GITHUB_USER="dein-user"
REPO_NAME="dein-repo"
BRANCH="main"
REPO_RAW_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${REPO_NAME}/${BRANCH}/lib"
TMP_DIR="$(mktemp -d -t bash-lib-XXXXXXXXXX)"
# ─────────────────────────────────────────────

log_info()  { echo -e "[\033[1;34mINFO\033[0m]  $*"; }
log_warn()  { echo -e "[\033[1;33mWARN\033[0m]  $*"; }
log_error() { echo -e "[\033[1;31mERROR\033[0m] $*" >&2; }
log_success() { echo -e "[\033[1;32mOK\033[0m]    $*"; }

cleanup() {
  [[ -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# ─────────────────────────────────────────────
# Fetch all .sh modules from remote lib/
fetch_all_modules() {
  log_info "Fetching module index from $REPO_RAW_URL"
  curl -fsSL "${REPO_RAW_URL}/index.txt" -o "$TMP_DIR/index.txt" || {
    log_error "Cannot fetch module index (index.txt)"
    exit 1
  }

  while IFS= read -r filename; do
    [[ -z "$filename" ]] && continue
    log_info "Downloading module: $filename"
    curl -fsSL "${REPO_RAW_URL}/${filename}" -o "$TMP_DIR/$filename" || {
      log_error "Failed to download $filename"
      exit 1
    }
    chmod 600 "$TMP_DIR/$filename"
  done < "$TMP_DIR/index.txt"
}

# ─────────────────────────────────────────────
# Source all downloaded modules
load_modules() {
  for f in "$TMP_DIR"/*.sh; do
    # shellcheck disable=SC1090
    source "$f"
  done
}

# ─────────────────────────────────────────────
# MAIN
fetch_all_modules
load_modules

log_success "All modules loaded from GitHub"

# Example usage
log_info "Modules ready – script logic goes here"
