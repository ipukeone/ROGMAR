# EspoCRM Application

This directory contains the configuration for deploying EspoCRM, a powerful open-source Customer Relationship Management (CRM) application. This setup includes the main EspoCRM application, a daemon for background jobs, a WebSocket server for real-time notifications, and the necessary database services.

## Application Overview

This EspoCRM deployment is composed of several services working together:

- **app:** The main EspoCRM web application.
- **espocrm_daemon:** The background daemon for scheduled jobs.
- **espocrm_websocket:** The WebSocket server for real-time features.
- **mariadb:** The MariaDB database for data storage.
- **mariadb_maintenance:** A service for periodic database backups.

## How to Use

1.  **Run the Setup Script:** From the root of the repository, run the `run.sh` script and point it to this directory:
    ```bash
    ./run.sh EspoCRM
    ```
    This will:
    - Clone the required service templates (`mariadb`, `espocrm_daemon`, etc.).
    - Merge all `docker-compose.*.yaml` files into a single `docker-compose.main.yaml`.
    - Consolidate all `.env` variables into a single `.env` file in this directory.
    - Copy required secret files and scripts.

2.  **Configure `.env`:** Review and edit the generated `.env` file. At a minimum, you must set `TRAEFIK_HOST` and `ESPOCRM_SITE_URL` to the domain you want to use for EspoCRM.

3.  **Provide Secrets:** Edit the secret file `secrets/ESPOCRM_ADMIN_PASSWORD` to provide a secure password for the admin user.

4.  **Deploy:** Start the application stack using Docker Compose:
    ```bash
    docker compose -f docker-compose.main.yaml up -d
    ```

## Configuration

### Environment Variables

The following environment variables can be configured in the `EspoCRM/.env` file:

- `IMAGE`: The Docker image for the EspoCRM application.
  - **Default:** `espocrm/espocrm`
- `APP_NAME`: The base name for the containers and services.
  - **Default:** `espocrm`
- `TRAEFIK_HOST`: The Traefik router rule for exposing EspoCRM.
  - **Example:** ``Host(`espocrm.your-domain.com`)``
- `TRAEFIK_PORT`: The internal port that the EspoCRM container listens on.
  - **Default:** `80`
- `ESPOCRM_PASSWORD_PATH`: The path to the directory containing the admin password secret file.
  - **Default:** `./secrets/`
- `ESPOCRM_PASSWORD_FILENAME`: The name of the file containing the admin password.
  - **Default:** `ESPOCRM_ADMIN_PASSWORD`
- `ESPOCRM_ADMIN_USERNAME`: The username for the initial administrator account.
  - **Default:** `admin`
- `ESPOCRM_SITE_URL`: The public-facing URL of the EspoCRM instance.
  - **Example:** `https://espocrm.your-domain.com`

### Required Templates

This application requires the following service templates, which are automatically pulled in by the `run.sh` script:

- `mariadb`
- `mariadb_maintenance`
- `espocrm_daemon`
- `espocrm_websocket`

### Scripts

This application includes a `scripts/setup.sh` file, which is executed by `run.sh` to set permissions on the application data directories.
