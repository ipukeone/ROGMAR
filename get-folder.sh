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
GREY='\033[1;30m'
MAGENTA='\033[0;35m'

# Function: log_ok
# Description: Logs a success message to stdout and to the logfile if configured.
# Arguments:
#   $*: The message to log.
# ───────────────────────────────────────
log_ok() {
  local msg="$*"
  echo -e "${GREEN}[OK]${RESET}    $msg"
  if [[ -n "${LOGFILE:-}" ]]; then
    echo -e "[OK]    $msg" >> "$LOGFILE"
  fi
}

# Function: log_info
# Description: Logs an informational message to stdout and to the logfile if configured.
# Arguments:
#   $*: The message to log.
# ───────────────────────────────────────
log_info() {
  local msg="$*"
  echo -e "${CYAN}[INFO]${RESET}  $msg"
  if [[ -n "${LOGFILE:-}" ]]; then
    echo -e "[INFO]  $msg" >> "$LOGFILE"
  fi
}

# Function: log_warn
# Description: Logs a warning message to stderr and to the logfile if configured.
# Arguments:
#   $*: The message to log.
# ───────────────────────────────────────
log_warn() {
  local msg="$*"
  echo -e "${YELLOW}[WARN]${RESET}  $msg" >&2
  if [[ -n "${LOGFILE:-}" ]]; then
    echo -e "[WARN]  $msg" >> "$LOGFILE"
  fi
}

# Function: log_error
# Description: Logs an error message to stderr and to the logfile if configured.
# Arguments:
#   $*: The message to log.
# ───────────────────────────────────────
log_error() {
  local msg="$*"
  echo -e "${RED}[ERROR]${RESET} $msg" >&2
  if [[ -n "${LOGFILE:-}" ]]; then
    echo -e "[ERROR] $msg" >> "$LOGFILE"
  fi
}

# Function: log_debug
# Description: Logs a debug message to stdout and to the logfile if the DEBUG global is true.
# Arguments:
#   $*: The message to log.
# ───────────────────────────────────────
log_debug() {
  local msg="$*"
  if [[ "${DEBUG:-false}" == true ]]; then
    echo -e "${GREY}[DEBUG]${RESET} $msg"
    if [[ -n "${LOGFILE:-}" ]]; then
      echo -e "[DEBUG] $msg" >> "$LOGFILE"
    fi
  fi
}

# Function: setup_logging
# Description:
#   Initializes the logging system for the script. It creates a dedicated log
#   directory, sets up a new log file named with a timestamp, and symlinks it
#   to 'latest.log' for easy access. It also prunes old logs to conserve space.
# Arguments:
#   $1 - The number of log files to retain. Defaults to 2.
# Globals:
#   - SCRIPT_DIR: The directory where the script is located.
#   - SCRIPT_BASE: The base name of the script, used for the log directory.
#   - LOGFILE: This global variable is set to the path of the new log file.
# ───────────────────────────────────────
setup_logging() {
  local log_retention_count="${1:-2}"

  # Construct log dir path
  local log_dir="${SCRIPT_DIR}/.${SCRIPT_BASE}.conf/logs"

  # Ensure log dir exists and assign logfile
  LOGFILE="${log_dir}/$(date +%Y%m%d-%H%M%S).log"
  ensure_dir_exists "$log_dir"

  # Symlink latest.log to current log
  touch "$LOGFILE" && sleep 0.2
  ln -sf "$LOGFILE" "$log_dir/latest.log"

  # Retain only the latest N logs
  local logs
  mapfile -t logs < <(
  find "$log_dir" -maxdepth 1 -type f -name '*.log' -printf "%T@ %p\n" |
  sort -nr | cut -d' ' -f2- | tail -n +$((log_retention_count + 1))
  )

  for old_log in "${logs[@]}"; do
    rm -f "$old_log"
  done
}

# ──────────────────────────────────────────────────────────────────────────────
# Usage Information
# ──────────────────────────────────────────────────────────────────────────────
# Function: usage
# Description:
#   Displays the help and usage information for the script, detailing the
#   command-line arguments, options, and operational notes.
# Globals:
#   - REPO_URL: The URL of the repository, shown in the usage message.
#   - BRANCH: The branch of the repository, shown in the usage message.
# ───────────────────────────────────────
usage() {
  cat <<EOF
Usage: $0 <folder-in-repo> [--debug] [--dry-run] [--force]

Downloads a specific folder from the GitHub repo:
  $REPO_URL (branch: $BRANCH)

Arguments:
  folder-in-repo   The folder path inside the repo to download. Must be relative and must not contain '..'.
  --debug          Enable debug output.
  --dry-run        Show what would be done without executing actions.
  --force          Force overwrite of existing 'run.sh' file in script directory.

Notes:
  - If the target directory already exists, you will be asked to confirm overwriting unless --dry-run is used.
  - If 'run.sh' is part of the downloaded folder and doesn't already exist in the script directory, it will be moved and made executable.
    Use --force to overwrite it even if it already exists.

EOF
}

# ──────────────────────────────────────────────────────────────────────────────
# Global Function Helpers
# ──────────────────────────────────────────────────────────────────────────────

# Function: ensure_dir_exists
# Description:
#   Checks if a directory exists at the specified path and creates it if it doesn't.
# Arguments:
#   $1 - The path of the directory to check and create.
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
# Description:
#   Parses command-line arguments, setting global flags and variables that
#   control the script's execution. It validates that a target folder has been
#   specified and initializes the logging system.
# Arguments:
#   $@ - The command-line arguments passed to the script.
# Globals:
#   - TARGET_DIR: Set to the path of the directory to be downloaded.
#   - REPO_SUBFOLDER: Set to the relative path of the folder within the repository.
#   - DEBUG, DRY_RUN, FORCE: Boolean flags set based on provided options.
# ───────────────────────────────────────
parse_args() {
  TARGET_DIR=""
  REPO_SUBFOLDER=""
  DEBUG=false
  DRY_RUN=false
  FORCE=false

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

  setup_logging "2"

  if [[ -n "$TARGET_DIR" ]]; then
    TARGET_DIR="${SCRIPT_DIR}/${TARGET_DIR}"
    log_debug "Repo folder: $REPO_SUBFOLDER and target directory: $TARGET_DIR"
  else
    log_error "Repo folder name not specified!"
    usage
    return 1
  fi
}

# Function: check_dependencies
# Description:
#   Verifies that required command-line tools (in this case, `git`) are
#   installed. If a dependency is missing, it prompts the user for installation.
# Globals:
#   - DRY_RUN: If true, the installation prompt is skipped.
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
# confirm_overwrite() {
#   if [[ -d "$TARGET_DIR" ]]; then
#     log_warn "Folder '$TARGET_DIR' already exists."
#     if [[ "$DRY_RUN" = true ]]; then
#       log_info "Dry-run: skipping removal of '$TARGET_DIR'."
#     else
#       read -r -p "Overwrite it? [y/N]: " confirm
#       if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
#         log_info "Aborted by user."
#         return 0
#       fi

#       rm -rf -- "$TARGET_DIR"
#       log_debug "Removed existing folder '$TARGET_DIR'"
#     fi
#   fi
# }

# Function: clone_sparse_checkout
# Description:
#   Performs a sparse checkout of the remote repository to efficiently download
#   only the specified subfolder. It creates a temporary directory for the clone,
#   configures sparse checkout, and fetches the desired folder.
# Globals:
#   - REPO_URL, BRANCH: Specifies the repository and branch to clone from.
#   - REPO_SUBFOLDER: The specific folder to check out.
#   - TMPDIR: Is set to the path of the new temporary directory.
#   - DRY_RUN: If true, the clone operation is skipped.
# ───────────────────────────────────────
clone_sparse_checkout() {
  #local repo_url="$1"
  #local branch="${2:-main}"
  #local repo_subfolder="$3"

  # Ensure required parameters are provided
  [[ -z "$REPO_URL" || -z "$REPO_SUBFOLDER" ]] && {
    log_error "Missing REPO_URL or REPO_SUBFOLDER."
    return 1
  }

  if [[ "$REPO_SUBFOLDER" == /* || "$REPO_SUBFOLDER" == *".."* ]]; then
    log_error "Invalid folder path: '$REPO_SUBFOLDER'"
    return 1
  fi

  if [[ "$DRY_RUN" = true ]]; then
    log_info "Dry-run: skipping git clone."
    return 0
  fi

  TMPDIR=$(mktemp -d)
  trap 'rm -rf -- "$TMPDIR"' EXIT
  log_debug "Created temp dir: $TMPDIR"

  git clone --quiet --filter=blob:none --no-checkout "$REPO_URL" "$TMPDIR" || {
    log_error "Failed to clone repo."
    return 1
  }

  if ! git -C "$TMPDIR" ls-tree -d --name-only "$BRANCH":"$REPO_SUBFOLDER" &>/dev/null; then
    log_error "Folder '$REPO_SUBFOLDER' not found in branch '$BRANCH'."
    return 1
  fi

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
    log_warn "Folder '$REPO_SUBFOLDER' not found in '$TMPDIR' directory."
  else
    log_debug "Checked out folder '$REPO_SUBFOLDER' successfully."
  fi
}

# Function: copy_files
# Description:
#   Copies the contents of the downloaded folder from the temporary directory to
#   the final target directory. It handles overwriting existing files and also
#   copies the `run.sh` script to the root if it's not already there.
# Globals:
#   - TARGET_DIR: The final destination for the folder contents.
#   - TMPDIR: The temporary directory where the folder was cloned.
#   - REPO_SUBFOLDER: The name of the folder being copied.
#   - DRY_RUN, FORCE: Control the copy and overwrite behavior.
# ───────────────────────────────────────
copy_files() {
  if [[ "$DRY_RUN" = true ]]; then
    log_info "Dry-run: skipping copying folder '$TARGET_DIR'."
    return 0
  fi

  if [[ "$FORCE" = true ]]; then
    log_info "Forcing copy to folder '$TARGET_DIR'."
  fi

  if [[ ! -d "$TMPDIR/$REPO_SUBFOLDER" ]]; then
    log_error "Folder '$REPO_SUBFOLDER' not found in '$TMPDIR' directory before copying."
    return 1
  fi

  if [[ -z $(ls -A "$TMPDIR/$REPO_SUBFOLDER") ]]; then
    log_warn "Folder '$REPO_SUBFOLDER' is empty."
  fi

  ensure_dir_exists "$TARGET_DIR"
  if cp -r --remove-destination "$TMPDIR/$REPO_SUBFOLDER"/. "$TARGET_DIR"/; then
    log_info "Folder '$REPO_SUBFOLDER' copied to '$TARGET_DIR' successfully."
  else
    log_error "Failed to copy folder."
    return 1
  fi

  if [[ ! -f "${SCRIPT_DIR}/run.sh" && -f "$TMPDIR/run.sh" ]] || [[ "$FORCE" = true && -f "$TMPDIR/run.sh" ]]; then
    cp --remove-destination "$TMPDIR/run.sh" "$SCRIPT_DIR/run.sh"
    chmod +x "${SCRIPT_DIR}/run.sh"
    log_info "Copied and made 'run.sh' executable."
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Main Execution
# ──────────────────────────────────────────────────────────────────────────────
# Function: main
# Description:
#   The main entry point for the script. It orchestrates the entire process:
#   1. Parses arguments.
#   2. Checks for dependencies.
#   3. Clones the repository to fetch the desired folder.
#   4. Checks for existing folders and handles overwrites.
#   5. Copies the files to the target directory.
# Arguments:
#   $@ - The command-line arguments passed to the script.
# ───────────────────────────────────────
main() {
  parse_args "$@"
  if [[ -n "$TARGET_DIR" ]]; then
    check_dependencies
    #confirm_overwrite
    clone_sparse_checkout
    if [[ -d "$TARGET_DIR" && "$FORCE" = false ]]; then
      log_error "Folder '$TARGET_DIR' already exist. Use --force to override it"
      return 1
    fi
    if [[ "$FORCE" = true || ! -d "$TARGET_DIR" ]]; then
      copy_files
    fi
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