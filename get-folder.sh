#!/bin/bash

# Folder name in the repo to download
FOLDER="$1"

# Check if folder name is provided
if [ -z "$FOLDER" ]; then
  echo "Usage: $0 <folder-in-repo>"
  return 0 2>/dev/null || exit 0
fi

# Check if target folder already exists
if [ -d "$FOLDER" ]; then
  echo "[WARN] Folder '$FOLDER' already exists."
  read -p "Overwrite it? [y/N]: " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "[INFO] Aborted."
    return 0 2>/dev/null || exit 0
  fi
  rm -rf "$FOLDER"
fi

# Temporary directory for sparse checkout
mkdir -p .git-tmp

# Clone repo quietly
git clone --quiet --filter=blob:none --no-checkout https://github.com/saervices/Docker.git .git-tmp &>/dev/null

# Enable sparse checkout and set the folder
git -C .git-tmp sparse-checkout init --cone &>/dev/null
git -C .git-tmp sparse-checkout set "$FOLDER" &>/dev/null

# Checkout the branch
git -C .git-tmp checkout main &>/dev/null

# Check if folder exists in the repo
if [ ! -d ".git-tmp/$FOLDER" ]; then
  echo "[ERROR] Folder '$FOLDER' not found in repo."
  rm -rf .git-tmp
  return 0 2>/dev/null || exit 0
fi

# Move the folder to current directory
mv ".git-tmp/$FOLDER" ./

# Only move run.sh if it doesn't already exist in the target folder
if [ ! -f "./run.sh" ] && [ -f ".git-tmp/run.sh" ]; then
  mv ".git-tmp/run.sh" "./"
  chmod +x "./run.sh"
  echo "[INFO] Moved and made './run.sh' executable."
fi

# Clean up
rm -rf .git-tmp

echo "[INFO] Folder '$FOLDER' downloaded successfully."