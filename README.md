# Docker Compose Template Sync & Setup Script

This repository contains reusable Docker Compose templates for various services (e.g., Redis, Postgres, MariaDB) and a helper script to sync and set them up in your projects.

---

## Features

- Clone or update templates from this repo in the background
- Create symlinks for required `docker-compose.*.yaml` files based on a main compose file in your project
- Merge `.env` files from templates into a single `.env.generated`
- Copy secrets from templates to your project
- Use a lockfile to track template version (Git commit hash)
- Support for `--dry-run` and `--force` modes in the sync script

---

## Usage

### 1. Download a Single Folder from GitHub Repo (e.g., `Template`)

This script downloads **only one specific folder** from the GitHub repository and places it in your current directory, using the same folder name as in the repo. No `.git` folder or other files are included.

#### How to use

1. Make the script executable:

```bash
chmod +x get-folder.sh
```

2. Run the script with the folder name from the repo as the argument:

```bash
./get-folder.sh Template
```

This will:

- Clone the repo with minimal data (no full history)  
- Checkout only the specified folder (`Template`)  
- Move that folder to your current directory  
- Remove all temporary files  

#### Script content (`get-folder.sh`)

```bash
#!/bin/bash

# Folder name in the repo to download
FOLDER="$1"

# Check if folder name is provided
if [ -z "$FOLDER" ]; then
  echo "Usage: $0 <folder-in-repo>"
  exit 1
fi

# Temporary directory for sparse checkout
mkdir .git-tmp

# Clone repo without checking out files and without full history
git clone --filter=blob:none --no-checkout https://github.com/saervices/Docker.git .git-tmp

# Enable sparse checkout and set the folder to download
git -C .git-tmp sparse-checkout init --cone
git -C .git-tmp sparse-checkout set "$FOLDER"

# Checkout the branch (adjust if your default branch is not main)
git -C .git-tmp checkout main

# Move the folder from temp directory to current working directory
mv ".git-tmp/$FOLDER" ./

# Clean up temporary directory
rm -rf .git-tmp
```

### 2. Run the setup script:

```bash
chmod +x run.sh && ./run.sh
```

- On first run, the script downloads or updates the **templates repo in the background**, creates symlinks for the required services (defined in `docker-compose.main.yaml`), merges `.env` files into `.env.generated`, and copies secrets. It does **not** start Docker Compose yet.

- Review and edit `.env.generated` as needed (e.g., update passwords, ports).

- Run `./run.sh` a second time to start Docker Compose with all services.

- Use `./run.sh --force` anytime to refresh templates and configs from GitHub.

- Use `./run.sh --dry-run` to see what changes would be made without applying them.

---

## Templates Repo Structure (background)

The templates repo (fetched automatically by the script) should have this layout:

```
/Docker
  /redis
    docker-compose.redis.yaml
    .env
    /secrets
      redis_password.txt
  /postgres
    docker-compose.postgres.yaml
    .env
    /secrets
      pg_pass.txt
```

---

## Security Considerations

To keep your containers secure, the templates and setup script encourage best practices such as:

- Dropping all unnecessary capabilities (`cap_drop: all`)
- Running containers with read-only file systems (`read_only: true`)
- Using Docker security options like `security_opt: ["no-new-privileges:true"]`

Please review and adjust the security settings in the individual service compose files as needed for your environment. Keeping privileges minimal helps reduce attack surface and potential risks.

---

## Requirements

- Bash shell
- Docker Compose v2 (`docker compose` command)
- Git (for cloning and updating templates)

---

Feel free to contribute new templates or improve the sync script!