#!/bin/bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# Constants & Defaults
# ──────────────────────────────────────────────────────────────────────────────
readonly REPO_URL="https://github.com/saervices/Docker.git"
readonly BRANCH="main"

# Get the directory of the script itself and the script name without .sh suffix
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
readonly SCRIPT_BASE="$(basename "${BASH_SOURCE[0]}" .sh)"

# ──────────────────────────────────────────────────────────────────────────────
# Logging Setup & Functions
# ──────────────────────────────────────────────────────────────────────────────

# Color codes for logging
# ───────────────────────────────────────
RESET='\033[0m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'

# Function: log_info
# ───────────────────────────────────────
log_info() {
  local msg="$*"
  echo -e "${GREEN}[INFO]${RESET}  $msg"
  if [[ -n "${LOGFILE:-}" ]]; then
    echo -e "[INFO]  $msg" >> "$LOGFILE"
  fi
}

# Function: log_warn
# ───────────────────────────────────────
log_warn() {
  local msg="$*"
  echo -e "${YELLOW}[WARN]${RESET}  $msg" >&2
  if [[ -n "${LOGFILE:-}" ]]; then
    echo -e "[WARN]  $msg" >> "$LOGFILE"
  fi
}

# Function: log_error
# ───────────────────────────────────────
log_error() {
  local msg="$*"
  echo -e "${RED}[ERROR]${RESET}  $msg" >&2
  if [[ -n "${LOGFILE:-}" ]]; then
    echo -e "[ERROR]  $msg" >> "$LOGFILE"
  fi
}

# Function: log_debug
# ───────────────────────────────────────
log_debug() {
  local msg="$*"
  if [[ "${DEBUG:-false}" == true ]]; then
    echo -e "${CYAN}[DEBUG]${RESET}  $msg"
  if [[ -n "${LOGFILE:-}" ]]; then
      echo -e "[DEBUG]  $msg" >> "$LOGFILE"
    fi
  fi
}

# Function: setup_logging
# Initializes logging file inside TARGET_DIR
# Keep only the latest $log_retention_count logs
# ───────────────────────────────────────
setup_logging() {
  local log_retention_count=2

  # Construct log dir path
  local log_dir="${SCRIPT_DIR}/.${SCRIPT_BASE}.conf/logs"

  # Ensure log dir exists and assign logfile
  LOGFILE="${log_dir}/$(date +%Y%m%d-%H%M%S).log"
  ensure_dir_exists "$log_dir"

  # Symlink latest.log to current log
  ln -sf "$(basename "$LOGFILE")" "$log_dir/latest.log"

  # Retain only the latest N logs
  local logs
  IFS=$'\n' read -r -d '' -a logs < <(
    find "$log_dir" -maxdepth 1 -type f -name '*.log' -printf "%T@ %p\n" |
    sort -nr | cut -d' ' -f2- | tail -n +$((log_retention_count + 1)) && printf '\0'
  )

  for old_log in "${logs[@]}"; do
    rm -f "$old_log"
  done
}

# ──────────────────────────────────────────────────────────────────────────────
# Usage Information
# ──────────────────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
Usage: $0 <folder-in-repo> [--debug] [--dry-run]

Downloads a specific folder from the GitHub repo:
  $REPO_URL (branch: $BRANCH)

Arguments:
  folder-in-repo   The folder path inside the repo to download. Must be relative and no '..'.
  --debug          Enable debug output.
  --dry-run        Show what would be done without executing.

Notes:
  - If the target-dir exists locally, you will be asked to confirm overwriting.

EOF
}

# ──────────────────────────────────────────────────────────────────────────────
# Global Function Helpers
# ──────────────────────────────────────────────────────────────────────────────

# Ensure a directory exists (create if missing)
# Arguments:
#   $1 - directory path
# ───────────────────────────────────────
ensure_dir_exists() {
  local dir="$1"
  if [[ -z "$dir" ]]; then
    log_error "ensure_dir_exists() called with empty path"
    return 1
  fi

  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir" || {
      log_error "Failed to create directory: $dir"
      return 1
    }
    log_info "Created directory: $dir"
  else
    log_debug "Directory already exists: $dir"
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Main Function
# ──────────────────────────────────────────────────────────────────────────────

# Function: parse_args
# Parses command-line arguments, sets globals and logging
# ───────────────────────────────────────
parse_args() {
  TARGET_DIR=""
  REPO_SUBFOLDER=""
  DEBUG=false
  DRY_RUN=false
  FORCE=false

  if [[ $# -eq 0 ]]; then
    usage
    return 1
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
      --force)
        FORCE=true
        shift
        ;;
      -*)
        log_error "Unknown option: $1"
        usage
        return 1
        ;;
      *)
        if [[ -z "${TARGET_DIR:-}" ]]; then
          TARGET_DIR="$1"
          REPO_SUBFOLDER="$1"
          shift
        else
          log_error "Multiple folder arguments are not supported."
          usage
          return 1
        fi
        ;;
    esac
  done

  log_debug "Debug mode enabled"
  if [[ "$DRY_RUN" = true ]]; then log_info "Dry-run mode enabled"; fi

  setup_logging

  if [[ -n "$TARGET_DIR" ]]; then
    TARGET_DIR="${SCRIPT_DIR}/${TARGET_DIR}"
    log_debug "Repo folder: $REPO_SUBFOLDER"
  # elif [[ -z "$TARGET_DIR" ]]; then
  #   TARGET_DIR="${SCRIPT_DIR}/"
  #   log_debug "Parsed folder: $TARGET_DIR"
  else
    log_error "Repo folder name not specified!"
    usage
    return 1
  fi
}

# Function: check_dependencies
# Verifies all required commands are available
# ───────────────────────────────────────
check_dependencies() {
  # Check git
  if ! command -v git &>/dev/null; then
    log_warn "git is not installed."
    if [[ "$DRY_RUN" = true ]]; then
      log_info "Dry-run: skipping git installation prompt."
      return 1
    fi
    read -r -p "Install git now? [y/N]: " install_git
    if [[ "$install_git" =~ ^[Yy]$ ]]; then
      if command -v apt-get &>/dev/null; then
        sudo apt-get update && sudo apt-get install -y git
      elif command -v yum &>/dev/null; then
        sudo yum install -y git
      else
        log_error "No supported package manager found to install git."
        return 1
      fi
      log_info "git installed successfully."
    else
      log_error "git is required. Aborting."
      return 1
    fi
  else
    log_debug "git is already installed."
  fi
}

# Function: confirm_overwrite
# Confirm Overwrite if Folder Exists
# ───────────────────────────────────────
confirm_overwrite() {
  if [[ -d "$TARGET_DIR" ]]; then
    log_warn "Folder '$TARGET_DIR' already exists."
    if [[ "$DRY_RUN" = true ]]; then
      log_info "Dry-run: skipping removal of '$TARGET_DIR'."
    else
      read -r -p "Overwrite it? [y/N]: " confirm
      if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Aborted by user."
        return 0
      fi

      rm -rf -- "$TARGET_DIR"
      log_debug "Removed existing folder '$TARGET_DIR'"
    fi
  fi
}

# Function: clone_sparse_checkout
# Clone Repo with Sparse Checkout
# ───────────────────────────────────────
clone_sparse_checkout() {
  if [[ "$DRY_RUN" = true ]]; then
    log_info "Dry-run: skipping git clone."
  else
    TMPDIR=$(mktemp -d)
    trap 'rm -rf -- "$TMPDIR"' EXIT
    log_debug "Created temp dir: $TMPDIR"

    git clone --quiet --filter=blob:none --no-checkout "$REPO_URL" "$TMPDIR" || {
      log_error "Failed to clone repo."
      return 1
    }

    git -C "$TMPDIR" sparse-checkout init --cone &>/dev/null || {
      log_error "Sparse checkout init failed."
      return 1
    }

    git -C "$TMPDIR" sparse-checkout set "$REPO_SUBFOLDER" &>/dev/null || {
      log_error "Sparse checkout set failed."
      return 1
    }

    git -C "$TMPDIR" checkout "$BRANCH" &>/dev/null || {
      log_error "Failed to checkout branch '$BRANCH'."
      return 1
    }
    if [[ ! -d "$TMPDIR/$REPO_SUBFOLDER" ]]; then
      log_warn "Folder '$REPO_SUBFOLDER' not found in temp directory."
    else
      log_debug "Checked out folder '$REPO_SUBFOLDER' successfully."
    fi
  fi
}

# Function: move_files
# Move Fetched Files to Local Folder
# ───────────────────────────────────────
move_files() {
  if [[ "$DRY_RUN" = true ]]; then
    log_info "Dry-run: skipping moving folder '$TARGET_DIR'."
    return 0
  fi

  if [[ ! -d "$TMPDIR/$REPO_SUBFOLDER" ]]; then
    log_error "Folder '$REPO_SUBFOLDER' not found in temp directory before moving."
    return 1
  fi

  if [[ -z $(ls -A "$TMPDIR/$REPO_SUBFOLDER") ]]; then
    log_warn "Folder '$REPO_SUBFOLDER' is empty."
  fi

  if mv -- "$TMPDIR/$REPO_SUBFOLDER" "$TARGET_DIR"; then
    log_info "Folder '$REPO_SUBFOLDER' downloaded to '$TARGET_DIR' successfully."
  else
    log_error "Failed to move folder."
    return 1
  fi

  if [[ ! -f "${SCRIPT_DIR}/run.sh" ]] && [[ -f "$TMPDIR/run.sh" ]] || [[ "$FORCE" = true ]]; then
    mv -- "$TMPDIR/run.sh" "$SCRIPT_DIR/"
    chmod +x "${SCRIPT_DIR}/run.sh"
    log_info "Moved and made 'run.sh' executable."
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Main Execution
# ──────────────────────────────────────────────────────────────────────────────
main() {
  parse_args "$@"  
  if [[ -n "$TARGET_DIR" ]]; then
    check_dependencies
    confirm_overwrite
    clone_sparse_checkout
    move_files
  else
    return 1
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Script Entry Point
# ──────────────────────────────────────────────────────────────────────────────
main "$@" || {
  exit 1
}