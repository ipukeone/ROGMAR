#!/bin/bash
set -euo pipefail

#######################################
# Constants
#######################################
readonly REPO_URL="https://github.com/saervices/Docker.git"
readonly BRANCH="main"
FOLDER=""
TMPDIR=""
DEBUG=false
POSITIONAL_ARGS=()

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
log_debug() { $DEBUG && echo -e "${CYAN}[DEBUG]${RESET} $*"; }

#######################################
# Usage Information
#######################################
usage() {
  cat <<EOF
Usage: $0 [--debug] <folder-in-repo>

Downloads a specific folder from the GitHub repo:
  $REPO_URL (branch: $BRANCH)

Arguments:
  folder-in-repo   The folder path inside the repo to download.

Options:
  --debug          Enable debug output.

Notes:
  - The folder name must not be absolute or contain '..' for safety.
  - If the folder exists locally, you will be asked to confirm overwriting.

EOF
}

#######################################
# Dependency Check
#######################################
check_dependencies() {
  if ! command -v git &>/dev/null; then
    log_error "git is not installed."
    exit 1
  fi
}

#######################################
# Parse Command Line Arguments
#######################################
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --debug)
        DEBUG=true
        ;;
      -*)
        log_error "Unknown option: $1"
        usage
        exit 1
        ;;
      *)
        POSITIONAL_ARGS+=("$1")
        ;;
    esac
    shift
  done

  set -- "${POSITIONAL_ARGS[@]:-}"
  validate_input "$@"
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
  log_debug "FOLDER set to: $FOLDER"
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
    log_debug "Deleted existing folder '$FOLDER'"
  fi
}

#######################################
# Clone Repo with Sparse Checkout
#######################################
clone_sparse_checkout() {
  TMPDIR=$(mktemp -d)
  trap 'rm -rf -- "$TMPDIR"' EXIT
  log_debug "Cloning into temp dir: $TMPDIR"

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

  log_debug "Sparse checkout succeeded: $FOLDER"
}

#######################################
# Move Fetched Files to Local Folder
#######################################
move_files() {
  mv -- "$TMPDIR/$FOLDER" ./ || {
    log_error "Failed to move folder."
    exit 1
  }

  if [ -z "$(ls -A "$FOLDER")" ]; then
    log_warn "Folder '$FOLDER' is empty."
  fi

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
  parse_args "$@"
  confirm_overwrite
  clone_sparse_checkout
  move_files
  log_info "Folder '$FOLDER' downloaded successfully."
}

#######################################
# Script Entry Point
#######################################
main "$@"