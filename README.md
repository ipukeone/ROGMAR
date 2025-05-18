# Docker Compose Template Sync & Setup Script

This repository provides reusable Docker Compose templates for common services like Redis, Postgres, and MariaDB, along with a helper script to sync and set them up in your projects effortlessly.

---

## Features

- Clone or update templates from this repository in the background  
- Automatically copy relevant `docker-compose.*.yaml` files for the services you need  
- Merge `.env` files from templates into one consolidated `.env` file  
- Copy secret files from templates to your project folder  
- Use a Git commit hash-based lockfile to track template versions  
- Supports `--dry-run`, `--force`, and `--update` options in the setup script  

---

## How to Use

### 1. Download a Single Folder from the GitHub Repo

If you want to use just one service template folder (e.g., `app_template`), you can download only that folder without cloning the whole repo.

#### Steps:

1. Make the downloader script executable:

```bash
chmod +x get-folder.sh
```

2. Run the script with the folder name from the repo as the argument:

```bash
./get-folder.sh app_template
```
This downloads only the specified folder from the repo, moves it to your current directory, and makes the included `run.sh` executable.

### 2. Run the setup script:

Change into the downloaded folder and run the setup script:

```bash
cd app_template/ && ./run.sh
```

On the first run, the script will:

- Download or update the full templates repo in the background  
- Copy the necessary Docker Compose files based on your app's compose file  
- Merge `.env` files from the templates into a single `.env`  
- Copy any secret files into your project folder  

After the setup finishes:

- Review and edit the generated `.env` file and secret files (e.g., update passwords or ports)  
- Start your containers using Docker Compose:

```bash
docker compose -f docker-compose.main.yaml up -d
```

If you want to refresh templates and configurations at any time, run:

```bash
./run.sh --force
```

To update all used Docker images (pull the latest), run:

```bash
./run.sh --update
```

To perform a dry run and see what changes would be made without applying them, run:

```bash
./run.sh --dry-run
```

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