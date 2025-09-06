# Authentik Application

This directory contains the configuration for deploying Authentik, a flexible and powerful open-source Identity Provider (IdP). This setup includes the main Authentik server, a worker, and the necessary database and cache services.

## Application Overview

This Authentik deployment is composed of several services working together:

- **app:** The main Authentik server application.
- **authentik-worker:** The background worker for handling asynchronous tasks.
- **postgresql:** The PostgreSQL database for data storage.
- **postgresql_backup:** A service for periodic database backups.
- **postgresql_restore:** A one-shot service for restoring the database from a backup.
- **redis:** A Redis instance for caching and message broking.

## How to Use

1.  **Run the Setup Script:** From the root of the repository, run the `run.sh` script and point it to this directory:
    ```bash
    ./run.sh Authentik
    ```
    This will:
    - Clone the required service templates (`postgresql`, `redis`, `authentik-worker`, etc.).
    - Merge all `docker-compose.*.yaml` files into a single `docker-compose.main.yaml`.
    - Consolidate all `.env` variables into a single `.env` file in this directory.
    - Copy required secret files.

2.  **Configure `.env`:** Review and edit the generated `.env` file. At a minimum, you must set the `TRAEFIK_HOST` to the domain you want to use for Authentik.

3.  **Provide Secrets:** Edit the secret files in the `secrets/` directory to provide secure passwords for the database and Authentik itself. The main secret to set is `AUTHENTIK_SECRET_KEY_PASSWORD`.

4.  **Deploy:** Start the application stack using Docker Compose:
    ```bash
    docker compose -f docker-compose.main.yaml up -d
    ```

## Configuration

### Environment Variables

The following environment variables can be configured in the `Authentik/.env` file:

- `IMAGE`: The Docker image for the Authentik server.
  - **Default:** `ghcr.io/goauthentik/server:latest`
- `APP_NAME`: The base name for the containers and services.
  - **Default:** `authentik`
- `TRAEFIK_HOST`: The Traefik router rule for exposing Authentik.
  - **Example:** ``Host(`authentik.your-domain.com`)``
- `TRAEFIK_PORT`: The internal port that Authentik listens on.
  - **Default:** `9000`
- `AUTHENTIK_SECRET_KEY_PASSWORD_PATH`: The path to the directory containing the secret key password file.
  - **Default:** `./secrets/`
- `AUTHENTIK_SECRET_KEY_PASSWORD_FILENAME`: The name of the file containing the secret key password.
  - **Default:** `AUTHENTIK_SECRET_KEY_PASSWORD`
- `AUTHENTIK_ERROR_REPORTING__ENABLED`: Enables or disables error reporting to Authentik.
  - **Default:** `true`

You can also configure email settings by uncommenting and filling in the `AUTHENTIK_EMAIL__*` variables in the `.env` file.

### Required Templates

This application requires the following service templates, which are automatically pulled in by the `run.sh` script:

- `postgresql`
- `postgresql_backup`
- `postgresql_restore`
- `redis`
- `authentik-worker`
