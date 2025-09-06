# Docker Compose Templates

This repository is a curated collection of Docker Compose templates designed to streamline the deployment of self-hosted applications. It provides a powerful scripting layer to manage reusable service templates, automate setup, and maintain consistent configurations across multiple projects.

## Core Concepts

The system is built around two main components: **pre-configured applications** and **reusable service templates**.

-   **Applications** (e.g., `Authentik/`, `Wiki.js/`) are ready-to-deploy setups for specific software. Each application has a `docker-compose.app.yaml` file that defines the main service and lists its dependencies.
-   **Templates** (in the `templates/` directory) are standardized, reusable configurations for common services like databases (`PostgreSQL`, `MariaDB`), caches (`Redis`), and utilities (`Socket Proxy`).

A helper script, `run.sh`, automates the process of assembling a final `docker-compose.main.yaml` file by fetching the required templates and merging their configurations.

## Getting Started

Follow these steps to deploy a new application using this repository.

### 1. Download an Application

First, choose an application you want to deploy from the list of [Available Applications](#available-applications). Use the `get-folder.sh` script to download it. This script uses Git's sparse checkout feature to fetch only the specified application directory without cloning the entire repository.

```bash
# Make the script executable
chmod +x get-folder.sh

# Download the application folder (e.g., Wiki.js)
./get-folder.sh Wiki.js
```

### 2. Run the Setup Script

Navigate into the newly created application directory and execute the `run.sh` script.

```bash
cd Wiki.js/
./run.sh
```

This script will perform the following actions:
-   **Check Dependencies:** Ensure that `git`, `yq`, and `rsync` are installed.
-   **Fetch Templates:** Clone the template repository into a temporary directory.
-   **Merge Configurations:**
    -   Read the `x-required-services` list from `docker-compose.app.yaml`.
    -   Copy the necessary template files (`docker-compose.*.yaml`, `.env`, `scripts/`, `secrets/`) into the application directory.
    -   Merge the YAML from the application and all required templates into a single `docker-compose.main.yaml`.
    -   Merge the environment variables from all `.env` files into a single, consolidated `.env` file.
-   **Set Permissions:** Execute any application-specific setup scripts (e.g., to set file permissions).
-   **Generate Passwords:** On the first run, it will automatically generate strong passwords for any required secrets.

### 3. Configure and Deploy

After the script finishes, you will have a complete, ready-to-run Docker Compose setup.

1.  **Review `.env`:** Open the main `.env` file and customize the environment variables, especially the `TRAEFIK_HOST` to set the domain for your service.
2.  **Review Secrets:** Check the files in the `secrets/` directory. While they are auto-generated, you may want to store them securely or replace them with your own.
3.  **Deploy:** Start the stack using Docker Compose.
    ```bash
    docker compose -f docker-compose.main.yaml up -d
    ```

## Scripts

### `run.sh`

This is the main orchestration script. It has several command-line options for advanced usage:

| Option                | Description                                                                  |
| --------------------- | ---------------------------------------------------------------------------- |
| `--force`             | Force a refresh of the templates and configurations, overwriting local changes. |
| `--update`            | Pull the latest Docker images for all services in the stack.                 |
| `--dry-run`           | Simulate the setup process without making any actual changes.                |
| `--delete-volumes`    | Stop the stack and delete all associated Docker volumes.                     |
| `--generate-password` | Generate new passwords for all secret files in the `secrets/` directory.     |

### `get-folder.sh`

A simple helper script to download a single application folder from the repository.

## Available Applications

| Application                               | Description                                                                                             |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| [Authentik](./Authentik/README.md)       | A flexible and powerful open-source Identity Provider (IdP).                                            |
| [EspoCRM](./EspoCRM/README.md)           | A powerful open-source Customer Relationship Management (CRM) application.                              |
| [Traefik](./Traefik/README.md)           | A modern reverse proxy and load balancer, configured as the main entrypoint for the self-hosted environment. |
| [VSCode](./VSCode/README.md)             | A `code-server` instance for running VS Code in a browser, enabling remote development.                 |
| [Wiki.js](./Wiki.js/README.md)           | A modern, lightweight, and powerful wiki engine.                                                        |

## Available Service Templates

These are the reusable building blocks located in the `templates/` directory.

| Template                                                      | Description                                                                                                   |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| [authentik-worker](./templates/authentik-worker/README.md)     | Handles background tasks for Authentik.                                                                       |
| [espocrm_daemon](./templates/espocrm_daemon/README.md)         | Runs background jobs for EspoCRM.                                                                             |
| [espocrm_websocket](./templates/espocrm_websocket/README.md)   | Enables real-time notifications in EspoCRM.                                                                   |
| [mariadb](./templates/mariadb/README.md)                       | A standardized and optimized MariaDB database service.                                                        |
| [mariadb_maintenance](./templates/mariadb_maintenance/README.md) | Performs scheduled backups (full, incremental, and dump) for a MariaDB database.                                |
| [postgresql](./templates/postgresql/README.md)                 | A standardized PostgreSQL database service.                                                                   |
| [postgresql_backup](./templates/postgresql_backup/README.md)   | Performs scheduled `pg_dump` backups for a PostgreSQL database.                                               |
| [postgresql_restore](./templates/postgresql_restore/README.md) | A one-shot service to restore a PostgreSQL database from a backup.                                            |
| [redis](./templates/redis/README.md)                           | A Redis service for caching and message broking.                                                              |
| [socketproxy](./templates/socketproxy/README.md)               | A secure proxy for the Docker socket, allowing controlled access to the Docker API.                           |
| [traefik_certs-dumper](./templates/traefik_certs-dumper/README.md) | Extracts SSL certificates from a Traefik `acme.json` file and can copy them to a remote server.                 |

## Security

This repository encourages security best practices:
-   **Least Privilege:** Containers are configured to drop all capabilities by default and only add back what is necessary.
-   **Read-Only Filesystems:** Where possible, container filesystems are set to read-only, with only specific data directories mounted as writable.
-   **No New Privileges:** The `no-new-privileges` security option is enabled to prevent privilege escalation.
-   **Socket Proxy:** Access to the Docker daemon is managed through a secure socket proxy with a fine-grained permission system, rather than exposing the main socket directly.

Review the security settings in each template's `docker-compose.*.yaml` file to ensure they meet your security requirements.

## Contributing

Contributions are welcome! Feel free to open an issue or submit a pull request to:
-   Add a new application or service template.
-   Improve the existing configurations or scripts.
-   Enhance the documentation.
