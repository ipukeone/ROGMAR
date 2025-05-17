#!/bin/bash

# ------------------------------------------------------------------------------
# run.sh – Docker Compose Template Sync & Setup Script
#
# Features:
# - Clones or updates a template repo from GitHub
# - Copies required docker-compose.*.yaml files based on main file (with --force overwrite)
# - Merges .env files from templates into a hash-based .env.generated.<hash>.env file
# - Creates a symlink .env.generated → latest merged file
# - Copies any required secrets from template directories only once
# - Cleans up older .env.generated.<hash>.env files (retains last 5)
# - Uses a lockfile to track template version (commit hash)
#
# Usage:
# ./run.sh            # First run: initializes templates, does NOT start Docker
# ./run.sh            # Second run: starts Docker Compose using generated files
# ./run.sh --force    # Forces update from GitHub and overwrites files
# ./run.sh --dry-run  # Simulates what would happen without changing anything
#
# Requires:
# - docker-compose.main.yaml with x-required-services
# - local Docker installation
# ------------------------------------------------------------------------------

set -e

GIT_REPO_URL="https://github.com/saervices/Docker"
LOCAL_CACHE_DIR="./.template-cache"
TEMPLATE_REPO="$LOCAL_CACHE_DIR/templates"
LOCKFILE=".template.lock"
MAIN_COMPOSE="docker-compose.main.yaml"
SECRETS_DIR="secrets"
BACKUP_DIR="./backup-$(date +%Y%m%d-%H%M%S)"
DRY_RUN=false
FORCE_UPDATE=false
START_COMPOSE=true
ENV_HASH_CONTENT=""

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      echo "→ Dry-run enabled: No actual changes will be made."
      ;;
    --force)
      FORCE_UPDATE=true
      echo "⚠️  Force update enabled: Templates and compose files will be refreshed."
      ;;
    *)
      echo "❓ Unknown argument: $1"
      exit 1
      ;;
  esac
  shift
done

echo "🌐 Checking for template updates from $GIT_REPO_URL..."

# Clone or update the template repo (sparse checkout of /templates)
if [ -d "$LOCAL_CACHE_DIR/.git" ]; then
  echo "🔄 Updating sparse-checkout of templates..."
  if [ "$FORCE_UPDATE" = true ]; then
    $DRY_RUN || git -C "$LOCAL_CACHE_DIR" pull --quiet
  else
    echo "💤 Skipping update – use --force to refresh templates."
  fi
else
  echo "📥 Cloning template repository (only 'templates/')..."
  $DRY_RUN || git init "$LOCAL_CACHE_DIR"
  $DRY_RUN || git -C "$LOCAL_CACHE_DIR" remote add origin "$GIT_REPO_URL"
  $DRY_RUN || git -C "$LOCAL_CACHE_DIR" config core.sparseCheckout true
  $DRY_RUN || echo "templates/" > "$LOCAL_CACHE_DIR/.git/info/sparse-checkout"
  DEFAULT_BRANCH=$(git ls-remote --symref "$GIT_REPO_URL" HEAD | grep 'ref:' | awk '{print $2}' | sed 's@refs/heads/@@')
  $DRY_RUN || git -C "$LOCAL_CACHE_DIR" pull --depth=1 origin "$DEFAULT_BRANCH"
fi

TEMPLATE_VERSION=$(git -C "$LOCAL_CACHE_DIR" rev-parse HEAD)
echo "📌 Using template version: $TEMPLATE_VERSION"

# Determine first run or already up to date
if [[ -f "$LOCKFILE" && "$FORCE_UPDATE" = false ]]; then
  CURRENT_LOCK=$(cat "$LOCKFILE")
  if [[ "$CURRENT_LOCK" == "$TEMPLATE_VERSION" ]]; then
    echo "✅ Templates already up-to-date (lockfile: $LOCKFILE)"
  else
    echo "ℹ️  Template updates available. Run with --force to apply."
    exit 0
  fi
else
  echo "🆕 First-time setup or forced update. Skipping Docker Compose startup."
  START_COMPOSE=false
  if [[ ! -f "$LOCKFILE" ]]; then
    echo "⚠️  First run detected: forcing template files copy"
    FORCE_UPDATE=true
  fi
fi

# Extract required services from main compose
echo "🔍 Parsing $MAIN_COMPOSE for required services..."
REQUIRES=$(grep -A10 'x-required-services:' "$MAIN_COMPOSE" | grep '-' | awk '{print $2}')
[ -z "$REQUIRES" ] && echo "⚠️  No services found in x-required-services." && exit 1

$DRY_RUN || mkdir -p "$SECRETS_DIR"
declare -A seen_vars
ENV_TMP_FILE=$(mktemp)

# Loop over required templates
for service in $REQUIRES; do
  compose_file="docker-compose.${service}.yaml"
  template_dir="$TEMPLATE_REPO/$service"
  template_env="$template_dir/.env"
  template_compose="$template_dir/docker-compose.$service.yaml"
  template_secrets="$template_dir/secrets"

  # Backup old compose
  if [ -f "$compose_file" ] && [ "$FORCE_UPDATE" = true ]; then
    echo "🛡️ Backing up existing $compose_file to $BACKUP_DIR/"
    $DRY_RUN || mkdir -p "$BACKUP_DIR"
    $DRY_RUN || cp "$compose_file" "$BACKUP_DIR/"
  fi

  # Copy compose file
  if [ ! -f "$compose_file" ] || [ "$FORCE_UPDATE" = true ]; then
    echo "📋 Copying compose file: $compose_file"
    $DRY_RUN || cp -f "$template_compose" "$compose_file"
  else
    echo "✅ Compose file already exists: $compose_file"
  fi

  # Merge .env content to temp
  if [ -f "$template_env" ]; then
    echo "📦 Importing .env from $service"
    while IFS= read -r line; do
      [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
      key=$(echo "$line" | cut -d= -f1)
      [ -n "${seen_vars[$key]}" ] && echo "⚠️  WARNING: Variable $key duplicated (now in $service)"
      seen_vars["$key"]=1
      $DRY_RUN || echo "$line" >> "$ENV_TMP_FILE"
    done < "$template_env"
    $DRY_RUN || echo "" >> "$ENV_TMP_FILE"
  fi

  # Copy secrets if missing
  if [ -d "$template_secrets" ]; then
    echo "🔐 Checking secrets for $service"
    for file in "$template_secrets"/*; do
      name=$(basename "$file")
      dest="$SECRETS_DIR/$name"
      if [ -f "$dest" ]; then
        echo "🔒 Secret '$name' exists – skipping"
      else
        echo "➕ Copying new secret: $name"
        $DRY_RUN || cp "$file" "$dest"
      fi
    done
  fi
done

# Append local .env
if [ -f ".env" ]; then
  echo "📦 Appending local .env"
  while IFS= read -r line; do
    [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
    key=$(echo "$line" | cut -d= -f1)
    [ -n "${seen_vars[$key]}" ] && echo "⚠️  WARNING: Variable $key duplicated (now in local .env)"
    seen_vars["$key"]=1
    $DRY_RUN || echo "$line" >> "$ENV_TMP_FILE"
  done < ".env"
fi

# Generate final hash-based env file
if [ "$DRY_RUN" = false ]; then
  ENV_HASH=$(sha256sum "$ENV_TMP_FILE" | cut -c1-12)
  ENV_FINAL=".env.generated.$ENV_HASH.env"
  mv "$ENV_TMP_FILE" "$ENV_FINAL"
  ln -sf "$ENV_FINAL" .env.generated
  echo "🧬 Created env file: $ENV_FINAL → .env.generated"

  # Update lockfile
  echo "$TEMPLATE_VERSION" > "$LOCKFILE"

  # Cleanup old env.generated.*.env (keep last 5)
  echo "🧹 Cleaning up old env files..."
  find . -maxdepth 1 -type f -name ".env.generated.*.env" \
    | sort -r | tail -n +6 | xargs -r rm -v
else
  echo "✅ Dry-run complete. Skipping final .env.generated generation."
  rm -f "$ENV_TMP_FILE"
fi

# Verify compose files
echo "🧪 Verifying docker-compose files..."
for service in $REQUIRES; do
  file="docker-compose.${service}.yaml"
  [ -f "$file" ] || { echo "❌ Missing $file. Re-run with --force."; exit 1; }
  echo "✅ Found: $file"
done

# Start Docker Compose
if [ "$DRY_RUN" = false ] && [ "$START_COMPOSE" = true ]; then
  echo "🚀 Starting Docker Compose..."
  COMPOSE_FILES=$(find . -maxdepth 1 -name "docker-compose.*.yaml" ! -name "*main*" -exec echo -f {} \;)
  docker compose -f "$MAIN_COMPOSE" $COMPOSE_FILES --env-file .env.generated up -d
else
  echo "ℹ️  Setup complete. Review .env.generated if needed. Re-run script to start Docker Compose."
fi