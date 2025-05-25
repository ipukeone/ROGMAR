#!/usr/bin/env bash
set -e #uo pipefail
trap cleanup_on_exit EXIT

# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# Usage:
#   ./run.sh [--dry-run] [--force] [--update] [--delete] [target-dir]
#
# Description:
#   This script automates the setup and management of Docker Compose projects using Git-based service templates.
#   It clones or updates the templates repo, backs up existing configuration files,
#   copies required service compose files and secrets, merges .env files and docker-compose files,
#   and optionally runs 'docker compose pull' to update images.
#
#   By default, it operates in the current directory. You can pass a target directory as the final argument.
#
# Options:
#   --dry-run      Show what would be done, but don't change any files.
#   --force        Force template update and file regeneration, even if the lockfile is up-to-date.
#   --update       Only pull the latest Docker images – skip file generation and merging steps.
#   --delete       Remove all Docker volumes created by this project (based on labels), then exit.
#
# Examples:
#   ./run.sh --force            # Force refresh templates and regenerate all compose/env files.
#   ./run.sh --dry-run          # Simulate actions without writing anything.
#   ./run.sh --update           # Only update images via 'docker compose pull'.
#   ./run.sh --delete           # Delete all volumes tied to this project and exit.
#   ./run.sh --force ./my-app   # Run in ./my-app directory with forced template refresh.
#
# Created by Særvices © 2025 — https://github.com/saervices
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# Constants
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# ──────────────────────────────────────────────────────────────────────────────
# Target directory parsing
# ──────────────────────────────────────────────────────────────────────────────
TARGET_DIR="."                                                                  # Set the target directory to "." if no target dir is specified
ARGS=()

for arg in "$@"; do
  if [[ "$arg" == --* ]]; then
    ARGS+=("$arg")
  else
    TARGET_DIR="$arg"
  fi
done

TARGET_DIR=$(realpath "$TARGET_DIR")

# ──────────────────────────────────────────────────────────────────────────────
# Docker Compose related files and directories
# ──────────────────────────────────────────────────────────────────────────────
RUN_DIR="$TARGET_DIR/.run.conf"                                                 # Folder for run.sh
MAIN_COMPOSE="$TARGET_DIR/docker-compose.app.yaml"                              # Main docker-compose file with service list
MERGED_COMPOSE="$TARGET_DIR/docker-compose.main.yaml"                           # Final merged docker-compose file generated by script
SECRETS_DIR="$TARGET_DIR/secrets"                                               # Directory to store secrets from templates

# ──────────────────────────────────────────────────────────────────────────────
# Git repository and local cache settings
# ──────────────────────────────────────────────────────────────────────────────
GIT_REPO_URL="https://github.com/saervices/Docker"                              # URL to the Docker templates Git repo
LOCAL_CACHE_DIR=$(mktemp -d)                                                    # Local folder to cache the repo
TEMPLATE_REPO="$LOCAL_CACHE_DIR/templates"                                      # Path inside cache where templates live
LOCKFILE="$RUN_DIR/template.lock"                                               # File storing the currently used template commit hash

# ──────────────────────────────────────────────────────────────────────────────
# Backup settings
# ──────────────────────────────────────────────────────────────────────────────
BACKUP_DIR="$RUN_DIR/backup"                                                    # Where old compose files are backed up
MAX_BACKUPS=2                                                                   # Max number of backup files to keep

# ──────────────────────────────────────────────────────────────────────────────
# Script control flags (default values)
# ──────────────────────────────────────────────────────────────────────────────
DRY_RUN=false                                                                   # If true, script will simulate actions without changing files
FORCE_UPDATE=false                                                              # Force update of templates and compose files, ignoring lockfile
UPDATE_IMAGES=false                                                             # if true, script will update all images (docker pull)
DELETE_VOLUMES=false                                                            # if true, script will delete all related volumes

# ──────────────────────────────────────────────────────────────────────────────
# Logging settings
# ──────────────────────────────────────────────────────────────────────────────
LOG_DIR="$RUN_DIR/logs"                                                         # Directory to store log files
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")                                          # Timestamp string for unique log filenames
LOG_FILE="$LOG_DIR/run.$TIMESTAMP.log"                                          # Path to the current log file
LOG_RETENTION_COUNT=2                                                           # Number of log files to keep (old ones will be deleted automatically)

# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# Logging function: prints to stdout AND appends to log file
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
mkdir -p "$LOG_DIR"
log() {
  echo "$@" | tee -a "$LOG_FILE"

  local logs=( $(ls -1t "$LOG_DIR"/run.*.log 2>/dev/null) )
  if [ "${#logs[@]}" -gt "$LOG_RETENTION_COUNT" ]; then
    for old_log in "${logs[@]:$LOG_RETENTION_COUNT}"; do
      rm -f "$old_log"
    done
  fi
}

# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# Argument parsing
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
parse_cli_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=true
        log "→ Dry-run enabled: No actual changes will be made."
        ;;
      --force)
        FORCE_UPDATE=true
        log "⚠️  Force update enabled: Templates and compose files will be refreshed."
        ;;
      --update)
        UPDATE_IMAGES=true
        log "⬆️ Update flag set: Docker images will be pulled."
        ;;
      --delete)
        DELETE_VOLUMES=true
        log "⬆️ Delete flag set: Docker volumes will be deleted."
        ;;
      *)
        log "❓ Unknown argument: $1"
        return
        ;;
    esac
    shift
  done
}

# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# Prerequisites
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
check_install_yq() {
  if command -v yq &> /dev/null; then return 0; fi

  log "❌ 'yq' is required but not installed."
  read -p "Do you want to install yq now? [Y/n] " answer
  answer=${answer:-Y}
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    log "⬇️ Installing yq..."
    if [[ "$(uname)" == "Darwin" ]]; then
      if command -v brew &> /dev/null; then
        brew install yq
      else
        log "Homebrew not found. Install yq manually: https://github.com/mikefarah/yq/releases"
        exit 1
      fi
    elif [[ "$(uname)" == "Linux" ]]; then
      sudo curl -L "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64" -o /usr/local/bin/yq
      sudo chmod +x /usr/local/bin/yq
    else
      log "Unsupported OS. Install manually: https://github.com/mikefarah/yq/releases"
      exit 1
    fi
    command -v yq &> /dev/null || { log "❌ yq install failed."; exit 1; }
    log "✅ yq installed."
  else
    log "❌ yq is required. Aborting."
    exit 1
  fi
}

# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# Template repo management
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
fetch_templates() {
  log "🌐 Checking for template updates from $GIT_REPO_URL..."

  if [ -d "$LOCAL_CACHE_DIR/.git" ]; then
    log "🔄 Updating sparse-checkout of templates..."
    if [ "$FORCE_UPDATE" = true ]; then
      $DRY_RUN || git -C "$LOCAL_CACHE_DIR" pull --quiet &> /dev/null
    else
      log "💤 Skipping update – use --force to refresh templates."
    fi
  else
    log "📥 Cloning template repository (only 'templates/')..."
    $DRY_RUN || git init --initial-branch=main "$LOCAL_CACHE_DIR" &> /dev/null
    $DRY_RUN || git -C "$LOCAL_CACHE_DIR" remote add origin "$GIT_REPO_URL" &> /dev/null
    $DRY_RUN || git -C "$LOCAL_CACHE_DIR" config core.sparseCheckout true &> /dev/null
    $DRY_RUN || echo "templates/" > "$LOCAL_CACHE_DIR/.git/info/sparse-checkout"
    DEFAULT_BRANCH=$(git ls-remote --symref "$GIT_REPO_URL" HEAD 2>/dev/null | grep 'ref:' | awk '{print $2}' | sed 's@refs/heads/@@')
    $DRY_RUN || git -C "$LOCAL_CACHE_DIR" pull --depth=1 origin "$DEFAULT_BRANCH" &> /dev/null
  fi

  TEMPLATE_VERSION=$(git -C "$LOCAL_CACHE_DIR" rev-parse HEAD 2>/dev/null || echo "")
  log "📌 Using template version: $TEMPLATE_VERSION"
}

check_template_state() {
  if [[ "$DRY_RUN" = true ]]; then
    log "💡 Dry-run: Skipping lockfile checks."
    return
  fi

  if [[ -f "$LOCKFILE" && "$FORCE_UPDATE" = false ]]; then
    CURRENT_LOCK=$(cat "$LOCKFILE")
    if [[ "$CURRENT_LOCK" == "$TEMPLATE_VERSION" ]]; then
      log "✅ Templates already up-to-date (lockfile: $LOCKFILE)"
    else
      log "ℹ️  Template updates available. Run with --force to apply."
      return
    fi
  fi
}

# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# Compose files + secrets
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
parse_required_services() {
  log "🔍 Parsing $MAIN_COMPOSE for required services..."
  REQUIRES=$(yq '.x-required-services[]' "$MAIN_COMPOSE" 2> /dev/null | sort -u)
  if [ -z "$REQUIRES" ]; then
    log "⚠️  No services found in x-required-services."
    [ "$DRY_RUN" = true ] || return
  else
    log "✅ Found required services:"
    while IFS= read -r service; do
      log "   • $service"
    done <<< "$REQUIRES"
  fi
}

backup_existing_compose_env() {
  if [[ "$FORCE_UPDATE" = true && -f "$LOCKFILE" ]]; then
    log "🛡️ Backing up existing compose files to $BACKUP_DIR/"
    mkdir -p "$BACKUP_DIR"
    for f in $TARGET_DIR/docker-compose.*.yaml; do
      if [[ "$f" != "$MERGED_COMPOSE" && -f "$f" ]]; then
        cp "$f" "$BACKUP_DIR/$(basename "$f").${TEMPLATE_VERSION:0:12}"
        log "  - Backed up $f"
      fi
    done
    if [[ -f "$TARGET_DIR/.env" ]]; then
      cp "$TARGET_DIR/.env" "$BACKUP_DIR/$(basename .env).${TEMPLATE_VERSION:0:12}"
      log "  - Backed up $TARGET_DIR/.env"
    fi
  else
    return
  fi

  # Function to get the base filename without the version suffix
  get_basename() {
    local filename=$(basename "$1")
    # Remove last extension part (the timestamp/version)
    echo "${filename%.*}"
  }

  # Clean old backups by keeping only $MAX_BACKUPS versions per base filename
  if [[ -d "$BACKUP_DIR" ]]; then
    log "🧹 Cleaning up old backups..."

    # Gather all backup files
    mapfile -t files < <(ls -1t "$BACKUP_DIR"/* 2>/dev/null)

    # Group files by their base name without version suffix
    declare -A groups=()
    for file in "${files[@]}"; do
      base=$(get_basename "$file")
      groups["$base"]=1
    done

    # For each base group, delete old backups beyond $MAX_BACKUPS
    for base in "${!groups[@]}"; do
      # Get all files matching the base prefix
      mapfile -t matches < <(ls -1tr "$BACKUP_DIR/${base}."* 2>/dev/null)

      # Calculate how many to delete (keep only $MAX_BACKUPS newest)
      num_to_delete=$((${#matches[@]} - MAX_BACKUPS))
      if (( num_to_delete > 0 )); then
        for ((i=0; i<num_to_delete; i++)); do
          log "🗑️ Deleting old backup file: ${matches[i]}"
          rm -f "${matches[i]}"
        done
      fi
    done
  fi
}

copy_templates_and_secrets() {
  [ "$DRY_RUN" = true ] || mkdir -p "$SECRETS_DIR"

  for service in $REQUIRES; do
    compose_file="$TARGET_DIR/docker-compose.${service}.yaml"
    template_dir="$TEMPLATE_REPO/$service"
    template_compose="$template_dir/docker-compose.$service.yaml"
    template_secrets="$template_dir/secrets"

    if [ ! -f "$compose_file" ] || [ "$FORCE_UPDATE" = true ]; then
      log "📋 Copying compose file: $compose_file"
      $DRY_RUN || cp -f "$template_compose" "$compose_file"
    else
      log "✅ Compose file exists: $compose_file"
    fi

    if [ -d "$template_secrets" ]; then
      log "🔐 Checking secrets for $service"
      for file in "$template_secrets"/*; do
        name=$(basename "$file")
        dest="$SECRETS_DIR/$name"
        if [ -f "$dest" ]; then
          log "🔒 Secret '$name' exists – skipping"
        else
          log "➕ Copying new secret: $name"
          $DRY_RUN || cp "$file" "$dest"
        fi
      done
    fi
  done
}

merge_env_files() {
  local output_file="$TARGET_DIR/.env"
  local local_env_file="$TARGET_DIR/app.env"
  local tmp_file
  tmp_file=$(mktemp)
  declare -A seen_vars=()

  if [[ -f "$output_file" && ! -f "$local_env_file" ]]; then
    mv "$output_file" "$local_env_file"
    log "ℹ️ Found legacy $output_file file – renamed to $local_env_file"
  fi

  if [[ -f "$output_file" && "$FORCE_UPDATE" != true ]]; then
    log "ℹ️ $output_file already exists – skipping merge (use --force to override)"
    return
  fi

  process_env_file() {
    local file=$1 source_name=$2
    while IFS= read -r line || [ -n "$line" ]; do
      [[ "$line" =~ ^#.*$ || -z "$line" ]] && echo "$line" >> "$tmp_file" && continue
      local key="${line%%=*}"
      [[ -z "$key" ]] && echo "$line" >> "$tmp_file" && continue
      if [[ -n "${seen_vars[$key]}" ]]; then
        log "⚠️ Duplicate variable '$key' found in $source_name (already from ${seen_vars[$key]}), skipping."
      else
        seen_vars["$key"]=$source_name
        line="$(echo "$line" | sed -E 's/^[[:space:]]*([^=[:space:]]+)[[:space:]]*=[[:space:]]*(.*)$/\1=\2/')"
        echo "$line" >> "$tmp_file"
      fi
    done < "$file"
    echo "" >> "$tmp_file"
  }

  > "$tmp_file"
  [[ -f "$local_env_file" ]] && process_env_file "$local_env_file" "local $local_env_file"
  for service in $REQUIRES; do
    [[ -f "$TEMPLATE_REPO/$service/.env" ]] && process_env_file "$TEMPLATE_REPO/$service/.env" "template $service"
  done
  mv "$tmp_file" "$output_file"
  rm -rf "$tmp_file"
  log "✅ Merged $local_env_file into $output_file"
}

merge_compose_files() {
  log "🔗 Merging $TARGET_DIR/docker-compose files..."

  TMP_DIR=$(mktemp -d)
  MERGE_INPUTS=()

  for f in $TARGET_DIR/docker-compose.*.yaml; do
    [[ "$f" == "$MERGED_COMPOSE" ]] && continue

    tmpf="$TMP_DIR/$(basename "$f")"

    # Clean file: remove x-required-services, comments, and ---
    yq 'del(.["x-required-services"])' "$f" | sed '/^---$/d' | sed 's/\s*#.*$//' > "$tmpf"

    # Get list of services
    services=$(yq e '.services | keys | .[]' "$tmpf")

    # # For each service, add env_file if missing
    # for svc in $services; do
    #   # Check if env_file exists for service
    #   has_env=$(yq e ".services.\"$svc\".env_file" "$tmpf")

    #   if [ "$has_env" == "null" ]; then
    #     yq e -i ".services.\"$svc\".env_file = [\".env\"]" "$tmpf"
    #   fi
    # done

    MERGE_INPUTS+=("$tmpf")
  done

  merge_key() {
    local key="$1"
    local files=("${MERGE_INPUTS[@]}")
    yq eval-all "select(has(\"$key\")) | .$key" "${files[@]}" |
      yq eval-all 'select(tag == "!!map") | . as $item ireduce ({}; . * $item)' -
  }

  services=$(merge_key services)
  volumes=$(merge_key volumes)
  secrets=$(merge_key secrets)
  networks=$(merge_key networks)

  {
    echo "---"
    echo "services:"
    echo "$services" | yq eval '.' - | sed 's/^/  /'
    echo ""
    echo "volumes:"
    echo "$volumes" | yq eval '.' - | sed 's/^/  /'
    echo ""
    echo "secrets:"
    echo "$secrets" | yq eval '.' - | sed 's/^/  /'
    echo ""
    echo "networks:"
    echo "$networks" | yq eval '.' - | sed 's/^/  /'
  } > "$MERGED_COMPOSE"

  rm -rf "$TMP_DIR"
  log "✅ Created merged compose file: $MERGED_COMPOSE"
}

verify_compose_files() {
  log "🧪 Verifying $TARGET_DIR/docker-compose files..."
  for service in $REQUIRES; do
    file="$TARGET_DIR/docker-compose.${service}.yaml"
    if [ ! -f "$file" ]; then
      if [ "$DRY_RUN" = false ]; then
        log "❌ Missing $file. Re-run with --force."
        return
      else
        log "⚠️  Dry-run: Would be missing $file."
      fi
    else
      log "✅ Found: $file"
    fi
  done
}

cleanup_cache() {
  if [ -d "$LOCAL_CACHE_DIR" ]; then
    log "🧹 Cleaning up template cache directory: $LOCAL_CACHE_DIR"
    $DRY_RUN || rm -rf "$LOCAL_CACHE_DIR"
  fi
}

cleanup_on_exit() {
  if [[ -f "$LOCKFILE" ]]; then
    rm -f "$LOCKFILE"
    debug "Lock file removed on exit"
  fi
  cleanup_cache
}

# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# Docker management
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
pull_docker_images() {
  log "⬇️ Pulling latest Docker images for services from $MERGED_COMPOSE..."

  local env_file="$TARGET_DIR/.env"

  if [[ -f "$env_file" ]]; then
    log "📄 Loading environment variables from $env_file"
    set -a
    # shellcheck source=/dev/null
    source "$env_file"
    set +a
  else
    log "⚠️ Env file $env_file not found. Cannot resolve image variables."
    return 1
  fi

  local services
  services=$(yq e '.services | keys | .[]' "$MERGED_COMPOSE")

  for svc in $services; do
    local image_raw image
    image_raw=$(yq e ".services.\"$svc\".image" "$MERGED_COMPOSE")
    image=$(eval echo "$image_raw")

    if [[ "$image" != "null" && -n "$image" ]]; then
      log "⬇️ Pulling image for service $svc: $image"
      if docker pull "$image" --quiet >/dev/null 2>&1; then
        log "✅ Pulled $image successfully"
      else
        log "❌ Failed to pull $image"
      fi
    else
      log "⚠️ No image defined for service $svc, skipping."
    fi
  done
}

delete_docker_volumes() {
  log "🧹 Deleting Docker volumes defined in $MERGED_COMPOSE..."

  local volumes
  volumes=$(yq e '.volumes | keys | .[]' "$MERGED_COMPOSE")

  for vol in $volumes; do
    local full_volume_name="${COMPOSE_PROJECT_NAME}_${vol}"
    if docker volume inspect "$full_volume_name" >/dev/null 2>&1; then
      log "🗑️ Removing volume: $full_volume_name"
      docker volume rm "$full_volume_name" >/dev/null 2>&1 \
        && log "✅ Removed $full_volume_name" \
        || log "❌ Failed to remove $full_volume_name"
    else
      log "⚠️ Volume $full_volume_name does not exist, skipping."
    fi
  done
}

# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
main() {
  parse_cli_args "${ARGS[@]}"
  check_install_yq
  fetch_templates
  check_template_state
  parse_required_services
  [ "$DRY_RUN" = false ] && backup_existing_compose_env || log "💡 Dry-run: Skipping Backing up existing compose and .env files."
  copy_templates_and_secrets
  [ "$DRY_RUN" = false ] && merge_env_files || log "💡 Dry-run: Skipping .env creation."
  [ "$DRY_RUN" = false ] && merge_compose_files || log "💡 Dry-run: Skipping $MERGED_COMPOSE generation."
  [ "$DRY_RUN" = false ] && echo "$TEMPLATE_VERSION" > "$LOCKFILE" && log "🔒 Updated lockfile: $LOCKFILE"
  verify_compose_files
  [ "$UPDATE_IMAGES" = true ] && pull_docker_images || log "💡 Skipping docker image update because UPDATE_IMAGES is false."
  [ "$DELETE_VOLUMES" = true ] && delete_docker_volumes || log "💡 Skipping docker volume deletion because DELETE_VOLUMES is false."
  cleanup_cache
  [ "$DRY_RUN" = false ] && log "ℹ️ Setup complete. Run "$MERGED_COMPOSE" script to start Docker Compose." || log "💡 Dry-run: "$MERGED_COMPOSE" not generated."
}

main "$@"