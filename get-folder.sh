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
DRY_RUN=false

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
log_debug() { [ "$DEBUG" = true ] && echo -e "${CYAN}[DEBUG]${RESET} $*"; }

#######################################
# Usage Information
#######################################
usage() {
  cat <<EOF
Usage: $0 <folder-in-repo> [--debug] [--dry-run]

Downloads a specific folder from the GitHub repo:
  $REPO_URL (branch: $BRANCH)

Arguments:
  folder-in-repo   The folder path inside the repo to download.
  --debug          Enable debug output.
  --dry-run        Show what would be done without executing.

Notes:
  - The folder name must not be absolute or contain '..' for safety.
  - If the folder exists locally, you will be asked to confirm overwriting.

EOF
}

#######################################
# Argument Parsing
#######################################
parse_args() {
  if [ $# -eq 0 ]; then
    usage
    exit 1
  fi

  while (( $# )); do
    case "$1" in
      --debug)
        DEBUG=true
        shift
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      -*)
        log_error "Unknown option: $1"
        usage
        exit 1
        ;;
      *)
        if [ -z "$FOLDER" ]; then
          FOLDER="$1"
          shift
        else
          log_error "Multiple folder arguments are not supported."
          usage
          exit 1
        fi
        ;;
    esac
  done

  if [[ "$FOLDER" == /* || "$FOLDER" == *..* ]]; then
    log_error "Unsafe folder name: '$FOLDER'"
    exit 1
  fi

  log_debug "Parsed folder: $FOLDER"
  if [ "$DEBUG" = true ]; then log_debug "Debug mode enabled"; fi
  if [ "$DRY_RUN" = true ]; then log_debug "Dry-run mode enabled"; fi
}

#######################################
# Dependency Check for git and yq
#######################################
check_dependencies() {
  # git check
  if ! command -v git &>/dev/null; then
    log_warn "git is not installed."
    if [[ "$DRY_RUN" = true ]]; then
      log_info "Dry-run: skipping git installation prompt."
      exit 1
    fi
    read -r -p "Install git now? [y/N]: " install_git
    if [[ "$install_git" =~ ^[Yy]$ ]]; then
      if command -v apt-get &>/dev/null; then
        sudo apt-get update && sudo apt-get install -y git
      elif command -v yum &>/dev/null; then
        sudo yum install -y git
      else
        log_error "No supported package manager found to install git."
        exit 1
      fi
      log_info "git installed successfully."
    else
      log_error "git is required. Aborting."
      exit 1
    fi
  else
    log_debug "git is already installed."
  fi
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
    if [ "$DRY_RUN" = true ]; then
      log_info "Dry-run: skipping removal of '$FOLDER'."
    else
      rm -rf -- "$FOLDER"
      log_debug "Removed existing folder '$FOLDER'"
    fi
  fi
}

#######################################
# Clone Repo with Sparse Checkout
#######################################
clone_sparse_checkout() {
  TMPDIR=$(mktemp -d)
  trap 'rm -rf -- "$TMPDIR"' EXIT
  log_debug "Created temp dir: $TMPDIR"

  if [ "$DRY_RUN" = true ]; then
    log_info "Dry-run: skipping git clone."
  else
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
      log_warn "Folder '$FOLDER' not found in temp directory."
    else
      log_debug "Checked out folder '$FOLDER' successfully."
    fi
  fi
}

#######################################
# Move Fetched Files to Local Folder
#######################################
move_files() {
  if [ "$DRY_RUN" = true ]; then
    log_info "Dry-run: skipping moving folder '$FOLDER'."
    return
  fi

  if [ ! -d "$TMPDIR/$FOLDER" ]; then
    log_error "Folder '$FOLDER' not found in temp directory before moving."
    exit 1
  fi

  if [ -z "$(ls -A "$TMPDIR/$FOLDER")" ]; then
    log_warn "Folder '$FOLDER' is empty."
  fi

  if mv -- "$TMPDIR/$FOLDER" ./; then
    log_info "Folder '$FOLDER' downloaded successfully."
  else
    log_error "Failed to move folder."
    exit 1
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
  parse_args "$@"
  check_dependencies
  confirm_overwrite
  clone_sparse_checkout
  move_files
}

#######################################
# Script Entry Point
#######################################
main "$@"