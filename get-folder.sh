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
mv ".git-tmp/run.sh" ./

# Clean up
rm -rf .git-tmp

# Make run.sh executable if present
if [ -f "$FOLDER/run.sh" ]; then
  chmod +x "$FOLDER/run.sh"
  echo "[INFO] Made '$FOLDER/run.sh' executable."
fi

echo "[INFO] Folder '$FOLDER' downloaded successfully."