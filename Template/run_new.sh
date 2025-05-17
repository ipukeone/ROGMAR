#!/bin/bash

# --------------------------------------------------------------------
# run.sh – Docker Compose Template Sync & Setup Script (Extended)
# --------------------------------------------------------------------

set -e

GIT_REPO_URL="https://github.com/saervices/Docker"
LOCAL_CACHE_DIR="./.template-cache"
TEMPLATE_REPO="$LOCAL_CACHE_DIR/templates"
TARGET_ENV_FILE=".env.generated"
LOCKFILE=".template.lock"
MAIN_COMPOSE="docker-compose.main.yaml"
SECRETS_DIR="secrets"
BACKUP_DIR="./backup-$(date +%Y%m%d-%H%M%S)"
ENV_HASH_FILE=".env.generated.hash"
DRY_RUN=false
FORCE_UPDATE=false
START_COMPOSE=true

# Parse command-line arguments
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

if [ -d "$LOCAL_CACHE_DIR/.git" ]; then
  echo "🔄 Updating sparse-checkout of templates..."
  if [ "$FORCE_UPDATE" = true ]; then
    $DRY_RUN || git -C "$LOCAL_CACHE_DIR" pull --quiet
  else
    echo "💤 Skipping update – use --force to refresh templates."
  fi
else
  echo "📥 Cloning template repository (only 'templates/' via sparse-checkout)..."
  $DRY_RUN || git init "$LOCAL_CACHE_DIR"
  $DRY_RUN || git -C "$LOCAL_CACHE_DIR" remote add origin "$GIT_REPO_URL"
  $DRY_RUN || git -C "$LOCAL_CACHE_DIR" config core.sparseCheckout true
  $DRY_RUN || echo "templates/" >| "$LOCAL_CACHE_DIR/.git/info/sparse-checkout"
  DEFAULT_BRANCH=$(git ls-remote --symref "$GIT_REPO_URL" HEAD | grep 'ref:' | awk '{print $2}' | sed 's@refs/heads/@@')
  $DRY_RUN || git -C "$LOCAL_CACHE_DIR" pull --depth=1 origin "$DEFAULT_BRANCH"
fi

TEMPLATE_VERSION=$(git -C "$LOCAL_CACHE_DIR" rev-parse HEAD)
echo "📌 Using template version: $TEMPLATE_VERSION"

if [[ -f "$LOCKFILE" && "$FORCE_UPDATE" = false ]]; then
  CURRENT_LOCK=$(cat "$LOCKFILE")
  if [[ "$CURRENT_LOCK" == "$TEMPLATE_VERSION" ]]; then
    echo "✅ Templates already up-to-date (lockfile: $LOCKFILE)"
  else
    echo "ℹ️  Template updates available. Run with --force to apply."
    exit 0
  fi
else
  echo "🆕 First-time setup detected or force update. Skipping Docker Compose startup."
  START_COMPOSE=false
  if [[ ! -f "$LOCKFILE" ]]; then
    echo "⚠️  First run detected: forcing template files copy"
    FORCE_UPDATE=true
  fi
fi

echo "🔍 Starting setup based on $MAIN_COMPOSE..."
REQUIRES=$(grep -A10 'x-required-services:' $MAIN_COMPOSE | grep '-' | awk '{print $2}')

if [ -z "$REQUIRES" ]; then
  echo "⚠️  No services found under 'x-required-services'."
  exit 1
fi

$DRY_RUN || mkdir -p $SECRETS_DIR
declare -A seen_vars
TEMP_ENV_CONTENT=""

for service in $REQUIRES; do
  compose_file="docker-compose.${service}.yaml"
  template_dir="$TEMPLATE_REPO/$service"
  template_env="$template_dir/.env"
  template_compose="$template_dir/docker-compose.$service.yaml"
  template_secrets="$template_dir/secrets"

  if [ -f "$compose_file" ] && ([ "$FORCE_UPDATE" = true ] || [ ! -f "$compose_file" ]); then
    echo "🛡️ Backing up existing $compose_file to $BACKUP_DIR/"
    $DRY_RUN || mkdir -p "$BACKUP_DIR"
    $DRY_RUN || cp "$compose_file" "$BACKUP_DIR/"
  fi

  if [ ! -f "$compose_file" ] || [ "$FORCE_UPDATE" = true ]; then
    echo "📋 Copying compose file: $compose_file"
    $DRY_RUN || cp -f "$template_compose" "$compose_file"
  else
    echo "✅ Compose file already exists: $compose_file"
  fi

  if [ -f "$template_env" ]; then
    echo "📦 Importing .env from $service"
    while IFS= read -r line; do
      [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
      key=$(echo "$line" | cut -d= -f1)
      if [[ -n "${seen_vars[$key]}" ]]; then
        echo "⚠️  WARNING: Variable $key is defined multiple times (now in $service)"
      fi
      seen_vars["$key"]=1
      TEMP_ENV_CONTENT+="$line"$'\n'
    done < "$template_env"
    TEMP_ENV_CONTENT+=$'\n'
  fi

  if [ -d "$template_secrets" ]; then
    echo "🔐 Checking secrets for $service"
    for file in "$template_secrets"/*; do
      name=$(basename "$file")
      dest="$SECRETS_DIR/$name"
      if [ -f "$dest" ]; then
        echo "🔒 Secret '$name' already exists – skipping copy"
      else
        echo "➕ Copying new secret: $name"
        $DRY_RUN || cp "$file" "$dest"
      fi
    done
  fi
done

if [ -f ".env" ]; then
  echo "📦 Appending local .env"
  while IFS= read -r line; do
    [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
    key=$(echo "$line" | cut -d= -f1)
    if [[ -n "${seen_vars[$key]}" ]]; then
      echo "⚠️  WARNING: Variable $key is defined multiple times (now in local .env)"
    fi
    seen_vars["$key"]=1
    TEMP_ENV_CONTENT+="$line"$'\n'
  done < ".env"
fi

# Create new .env.generated only if content changed
NEW_HASH=$(echo "$TEMP_ENV_CONTENT" | sha256sum | awk '{print $1}')
OLD_HASH=$(cat "$ENV_HASH_FILE" 2>/dev/null || echo "")

if [ "$NEW_HASH" != "$OLD_HASH" ]; then
  echo "🆕 .env.generated content changed. Saving new version..."
  $DRY_RUN || echo "$TEMP_ENV_CONTENT" > "$TARGET_ENV_FILE"
  $DRY_RUN || echo "$NEW_HASH" > "$ENV_HASH_FILE"
else
  echo "✅ No changes to .env.generated. Skipping rewrite."
fi

# Update lockfile
if [ "$DRY_RUN" = false ]; then
  echo "$TEMPLATE_VERSION" > "$LOCKFILE"
fi

echo "🔍 Verifying docker-compose files..."
for service in $REQUIRES; do
  compose_file="docker-compose.${service}.yaml"
  if [ ! -f "$compose_file" ]; then
    echo "❌ ERROR: '$compose_file' does not exist."
    echo "→ Please run './run.sh --force' to recreate missing files."
    exit 1
  fi
  echo "✅ Verified: $compose_file"
done

if [ "$DRY_RUN" = true ]; then
  echo "✅ Dry-run finished. No docker commands were executed."
else
  if [ "$START_COMPOSE" = true ]; then
    echo "🚀 Starting Docker Compose..."
    COMPOSE_FILES=$(find . -maxdepth 1 -name "docker-compose.*.yaml" ! -name "*main*" -exec echo -f {} \;)
    docker compose -f $MAIN_COMPOSE $COMPOSE_FILES --env-file $TARGET_ENV_FILE up -d
  else
    echo "ℹ️  Setup complete. Please review and edit $TARGET_ENV_FILE if needed, then run ./run.sh again to start Docker Compose."
  fi
fi
