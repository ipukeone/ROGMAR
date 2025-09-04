# Wiki.js Application

This directory contains the configuration for deploying Wiki.js, a modern, lightweight, and powerful wiki engine. This setup includes the main Wiki.js application and the necessary database services.

## Application Overview

This Wiki.js deployment is composed of several services working together:

- **app:** The main Wiki.js web application.
- **postgresql:** The PostgreSQL database for data storage.
- **postgresql_backup:** A service for periodic database backups.
- **postgresql_restore:** A one-shot service for restoring the database from a backup.

## How to Use

1.  **Run the Setup Script:** From the root of the repository, run the `run.sh` script and point it to this directory:
    ```bash
    ./run.sh Wiki.js
    ```
    This will:
    - Clone the required service templates (`postgresql`, `postgresql_backup`, etc.).
    - Merge all `docker-compose.*.yaml` files into a single `docker-compose.main.yaml`.
    - Consolidate all `.env` variables into a single `.env` file in this directory.
    - Copy required secret files.

2.  **Configure `.env`:** Review and edit the generated `.env` file. You must set `TRAEFIK_HOST` to the domain you want to use for Wiki.js.

3.  **Provide Secrets:** Ensure the `secrets/POSTGRES_PASSWORD` file from the `postgresql` template contains a secure password.

4.  **Deploy:** Start the application stack using Docker Compose:
    ```bash
    docker compose -f docker-compose.main.yaml up -d
    ```

## Configuration

### Environment Variables

The following environment variables can be configured in the `Wiki.js/.env` file:

- `IMAGE`: The Docker image for the Wiki.js application.
  - **Default:** `requarks/wiki`
- `APP_NAME`: The base name for the containers and services.
  - **Default:** `wikijs`
- `TRAEFIK_HOST`: The Traefik router rule for exposing Wiki.js.
  - **Example:** ``Host(`wikijs.your-domain.com`)``
- `TRAEFIK_PORT`: The internal port that Wiki.js listens on.
  - **Default:** `3000`

The following environment variables are set directly in the `docker-compose.app.yaml` file to configure the database connection:

- `DB_TYPE`: `postgres`
- `DB_HOST`: `${APP_NAME}-postgresql`
- `DB_PORT`: `5432`
- `DB_PASS_FILE`: `/run/secrets/POSTGRES_PASSWORD`
- `DB_USER`: `${APP_NAME}`
- `DB_NAME`: `${APP_NAME}`

### Required Templates

This application requires the following service templates, which are automatically pulled in by the `run.sh` script:

- `postgresql`
- `postgresql_backup`
- `postgresql_restore`

### Initialization Script

This application includes a `scripts/init.sql` file. This script can be used to perform initial database setup, such as creating extensions or setting up initial data. It is mounted into the `postgresql` container and executed when the database is first created. By default, it is empty.
