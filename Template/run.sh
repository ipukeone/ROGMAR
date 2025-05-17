#!/bin/bash

# ------------------------------------------------------------------------------
# run.sh – Docker Compose Template Sync & Setup Script
#
# Features:
# - Clones or updates a template repo from GitHub
# - Symlinks required docker-compose.*.yaml files based on main file
# - Merges .env files from templates into .env.generated
# - Copies any required secrets from template directories
# - Uses a lockfile to track template version (commit hash)
#
# Usage:
# ./run.sh            # First run: initializes templates, does NOT start Docker
# ./run.sh            # Second run: starts Docker Compose using generated files
# ./run.sh --force    # Forces update from GitHub and rebuilds everything
# ./run.sh --dry-run  # Simulates what would happen without changing anything
#
# Workflow:
# 1. On first run:
#    - Sets up templates, env and secrets
#    - Skips 'docker compose up -d' to let you review .env.generated
#
# 2. On second run (with unchanged template version):
#    - Starts Docker Compose with all template services
#
# 3. You can update the template repo anytime using '--force'
#
# Notes:
# - Requires a 'docker-compose.main.yaml' with x-required-services defined
# - Combines environment variables from templates and local .env
# ------------------------------------------------------------------------------

set -e

GIT_REPO_URL="https://github.com/saervices/Docker"
LOCAL_CACHE_DIR="./.template-cache"
TEMPLATE_REPO="$LOCAL_CACHE_DIR/templates"
TARGET_ENV_FILE=".env.generated"
LOCKFILE=".template.lock"
MAIN_COMPOSE="docker-compose.main.yaml"
SECRETS_DIR="secrets"
DRY_RUN=false
FORCE_UPDATE=false
START_COMPOSE=true

if [[ "$1" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "→ Dry-run enabled: No actual changes will be made."
elif [[ "$1" == "--force" ]]; then
  FORCE_UPDATE=true
  echo "⚠️  Force update enabled: Templates will be refreshed regardless of lockfile."
fi

echo "🌐 Checking for template updates from $GIT_REPO_URL..."

if [ -d "$LOCAL_CACHE_DIR/.git" ]; then
  echo "🔄 Updating local clone..."
  git -C "$LOCAL_CACHE_DIR" pull --quiet
else
  echo "📥 Cloning template repository..."
  git clone --depth=1 "$GIT_REPO_URL" "$LOCAL_CACHE_DIR"
fi

# Get latest commit hash for lockfile
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
  echo "🆕 First-time setup detected. Skipping Docker Compose startup."
  START_COMPOSE=false
fi

echo "🔍 Starting setup based on $MAIN_COMPOSE..."

# Extract required services from x-required-services
REQUIRES=$(grep -A10 'x-required-services:' $MAIN_COMPOSE | grep '-' | awk '{print $2}')

if [ -z "$REQUIRES" ]; then
  echo "⚠️  No services found under 'x-required-services'."
  exit 1
fi

$DRY_RUN || rm -f $TARGET_ENV_FILE
$DRY_RUN || mkdir -p $SECRETS_DIR

declare -A seen_vars

for service in $REQUIRES; do
  compose_file="docker-compose.${service}.yaml"
  template_dir="$TEMPLATE_REPO/$service"
  template_env="$template_dir/.env"
  template_compose="$template_dir/docker-compose.$service.yaml"
  template_secrets="$template_dir/secrets"

  # Symlink the Compose file
  if [ ! -L "$compose_file" ]; then
    echo "🔗 Creating symlink: $compose_file"
    $DRY_RUN || ln -s "$template_compose" "$compose_file"
  else
    echo "✅ Symlink already exists: $compose_file"
  fi

  # Merge .env
  if [ -f "$template_env" ]; then
    echo "📦 Importing .env from $service"
    while IFS= read -r line; do
      [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
      key=$(echo "$line" | cut -d= -f1)
      if [[ -n "${seen_vars[$key]}" ]]; then
        echo "⚠️  WARNING: Variable $key is defined multiple times (now in $service)"
      fi
      seen_vars["$key"]=1
      $DRY_RUN || echo "$line" >> $TARGET_ENV_FILE
    done < "$template_env"
    $DRY_RUN || echo "" >> $TARGET_ENV_FILE
  fi

  # Copy secrets
  if [ -d "$template_secrets" ]; then
    echo "🔐 Copying secrets for $service"
    for file in "$template_secrets"/*; do
      name=$(basename "$file")
      dest="$SECRETS_DIR/$name"
      if [ -f "$dest" ]; then
        echo "⚠️  Secret $name already exists – will be overwritten"
      fi
      $DRY_RUN || cp "$file" "$dest"
    done
  fi
done

# Append local .env
if [ -f ".env" ]; then
  echo "📦 Appending local .env"
  while IFS= read -r line; do
    [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
    key=$(echo "$line" | cut -d= -f1)
    if [[ -n "${seen_vars[$key]}" ]]; then
      echo "⚠️  WARNING: Variable $key is defined multiple times (now in local .env)"
    fi
    seen_vars["$key"]=1
    $DRY_RUN || echo "$line" >> $TARGET_ENV_FILE
  done < ".env"
fi

# Update lockfile
if [ "$DRY_RUN" = false ]; then
  echo "$TEMPLATE_VERSION" > "$LOCKFILE"
fi

# Start docker-compose
if [ "$DRY_RUN" = true ]; then
  echo "✅ Dry-run finished. No docker commands were executed."
else
  if [ "$START_COMPOSE" = true ]; then
    echo "🚀 Starting Docker Compose..."
    COMPOSE_FILES=$(ls docker-compose.*.yaml | grep -v main | xargs -n1 echo -f)
    docker compose -f $MAIN_COMPOSE $COMPOSE_FILES --env-file $TARGET_ENV_FILE up -d
  else
    echo "ℹ️  Setup complete. Please review and edit .env.generated if needed, then run ./run.sh again to start Docker Compose."
  fi
fi


