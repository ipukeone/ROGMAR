#!/bin/bash

## Usage
# ./run.sh              # normal mode
# ./run.sh --dry-run    # preview changes without executing anything


set -e

TEMPLATE_REPO=~/docker-compose-templates/templates
TARGET_ENV_FILE=".env.generated"
MAIN_COMPOSE="docker-compose.main.yaml"
SECRETS_DIR="secrets"
DRY_RUN=false

if [[ "$1" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "→ Dry-run enabled: No actual changes will be made."
fi

echo "🔍 Starting setup based on $MAIN_COMPOSE..."

# Extract required services from x-required-services
REQUIRES=$(grep -A10 'x-required-services:' $MAIN_COMPOSE | grep '-' | awk '{print $2}')

if [ -z "$REQUIRES" ]; then
  echo "⚠️  No services found under 'x-required-services'."
  exit 1
fi

# Clean up previous generated files
$DRY_RUN || rm -f $TARGET_ENV_FILE
$DRY_RUN || mkdir -p $SECRETS_DIR

# Track seen env variables to detect duplicates
declare -A seen_vars

for service in $REQUIRES; do
  compose_file="docker-compose.${service}.yaml"
  template_dir="$TEMPLATE_REPO/$service"
  template_env="$template_dir/.env"
  template_secrets="$template_dir/secrets"

  # Symlink the Compose file
  if [ ! -L "$compose_file" ]; then
    echo "🔗 Creating symlink: $compose_file"
    $DRY_RUN || ln -s "$template_dir/docker-compose.$service.yaml" "$compose_file"
  else
    echo "✅ Symlink already exists: $compose_file"
  fi

  # Merge .env from template
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

# Append local .env if available
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

# Run docker-compose
if [ "$DRY_RUN" = true ]; then
  echo "✅ Dry-run finished. No docker commands were executed."
else
  echo "🚀 Starting Docker Compose..."
  COMPOSE_FILES=$(ls docker-compose.*.yaml | grep -v main | xargs -n1 echo -f)
  docker compose -f $MAIN_COMPOSE $COMPOSE_FILES --env-file $TARGET_ENV_FILE up -d
fi