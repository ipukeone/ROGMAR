#!/bin/bash
set -euo pipefail

#######################################
# Constants
#######################################
readonly REPO_URL="https://github.com/saervices/Docker.git"
readonly BRANCH="main"
FOLDER=""
TMPDIR=""

#######################################
# Color Codes for Logging
#######################################
RESET='\033[0m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'

#######################################
# Logging Functions
#######################################
log_info()  { echo -e "${GREEN}[INFO]${RESET}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${RESET}  $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_debug() { echo -e "${CYAN}[DEBUG]${RESET} $*"; }

#######################################
# Usage Information
#######################################
usage() {
  cat <<EOF
Usage: $0 <folder-in-repo>

Downloads a specific folder from the GitHub repo:
  $REPO_URL (branch: $BRANCH)

Arguments:
  folder-in-repo   The folder path inside the repo to download.

Notes:
  - The folder name must not be absolute or contain '..' for safety.
  - If the folder exists locally, you will be asked to confirm overwriting.

EOF
}

#######################################
# Install git if missing (with prompt)
#######################################
install_git_if_missing() {
  if command -v git &>/dev/null; then
    log_debug "git is already installed."
    return 0
  fi

  log_warn "'git' not found."

  if [[ $EUID -ne 0 ]]; then
    log_error "Cannot install 'git' automatically without root privileges."
    exit 1
  fi

  read -r -p "Do you want to install 'git' now? [y/N]: " answer
  if [[ ! "$answer" =~ ^[Yy]$ ]]; then
    log_error "'git' is required but not installed. Aborting."
    exit 1
  fi

  if command -v apt-get &>/dev/null; then
    log_info "Installing git using apt-get..."
    apt-get update -qq && apt-get install -y git
  elif command -v apk &>/dev/null; then
    log_info "Installing git using apk..."
    apk add --no-cache git
  elif command -v dnf &>/dev/null; then
    log_info "Installing git using dnf..."
    dnf install -y git
  elif command -v yum &>/dev/null; then
    log_info "Installing git using yum..."
    yum install -y git
  elif command -v pacman &>/dev/null; then
    log_info "Installing git using pacman..."
    pacman -Sy --noconfirm git
  else
    log_error "No supported package manager found. Install 'git' manually."
    exit 1
  fi

  if ! command -v git &>/dev/null; then
    log_error "Failed to install 'git'."
    exit 1
  fi

  log_info "'git' installed successfully."
}

#######################################
# Dependency Check
#######################################
check_dependencies() {
  install_git_if_missing
}

#######################################
# Input Validation
#######################################
validate_input() {
  if [ $# -lt 1 ] || [ -z "${1-}" ]; then
    usage
    exit 1
  fi

  local input="$1"
  if [[ "$input" == /* || "$input" == *..* ]]; then
    log_error "Unsafe folder name: '$input'"
    exit 1
  fi

  FOLDER="$input"
}

#######################################
# Confirm Overwrite if Folder Exists
#######################################
confirm_overwrite() {
  if [ -d "$FOLDER" ]; then
    log_warn "Folder '$FOLDER' already exists."
    read -r -p "Overwrite it? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      log_info "Aborted by user."
      exit 0
    fi
    rm -rf -- "$FOLDER"
  fi
}

#######################################
# Clone Repo with Sparse Checkout
#######################################
clone_sparse_checkout() {
  TMPDIR=$(mktemp -d)
  trap 'rm -rf -- "$TMPDIR"' EXIT

  git clone --quiet --filter=blob:none --no-checkout "$REPO_URL" "$TMPDIR" || {
    log_error "Failed to clone repo."
    exit 1
  }

  git -C "$TMPDIR" sparse-checkout init --cone &>/dev/null || {
    log_error "Sparse checkout init failed."
    exit 1
  }

  git -C "$TMPDIR" sparse-checkout set "$FOLDER" &>/dev/null || {
    log_error "Sparse checkout set failed."
    exit 1
  }

  git -C "$TMPDIR" checkout "$BRANCH" &>/dev/null || {
    log_error "Git checkout failed."
    exit 1
  }

  if [ ! -d "$TMPDIR/$FOLDER" ]; then
    log_error "Folder '$FOLDER' not found in repo."
    exit 1
  fi
}

#######################################
# Move Fetched Files to Local Folder
#######################################
move_files() {
  if [ ! -d "$TMPDIR/$FOLDER" ]; then
    log_error "Folder '$FOLDER' not found in temp directory before moving."
    exit 1
  fi

  if [ -z "$(ls -A "$TMPDIR/$FOLDER")" ]; then
    log_warn "Folder '$FOLDER' is empty."
  fi

  mv -- "$TMPDIR/$FOLDER" ./ || {
    log_error "Failed to move folder."
    exit 1
  }

  if [ ! -f "./run.sh" ] && [ -f "$TMPDIR/run.sh" ]; then
    mv -- "$TMPDIR/run.sh" "./"
    chmod +x "./run.sh"
    log_info "Moved and made './run.sh' executable."
  fi
}


#######################################
# Main Function
#######################################
main() {
  check_dependencies
  validate_input "$@"
  confirm_overwrite
  clone_sparse_checkout
  move_files
  log_info "Folder '$FOLDER' downloaded successfully."
}

#######################################
# Script Entry Point
#######################################
main "$@"