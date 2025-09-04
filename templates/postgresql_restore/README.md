# PostgreSQL Restore Service

This template provides a one-shot service for restoring a PostgreSQL database from a backup file. It is designed to be run manually when a restore is needed, and it will exit after the restore process is complete.

## Service Overview

- **Image:** The Docker image for the service is specified by the `POSTGRES_IMAGE` variable, which should be the same as the main PostgreSQL service.
- **Restart Policy:** The restart policy is set to `no`, ensuring the container runs once and then stops.
- **Networking:** The service connects to the `backend` network to communicate with the `postgresql` service.
- **Volumes:** It mounts a local `./restore` directory, where it expects to find the backup file to be restored.
- **Scripts:** The core logic is contained within the `scripts/restore-cron.sh` script, which is executed by the container's entrypoint.
- **Dependencies:** This service depends on the `postgresql` service being healthy before it starts.

## Configuration

### Environment Variables

This template does not have a dedicated `.env` file. The following environment variables are passed from the main application's environment:

- `DB_HOST`: The hostname of the PostgreSQL service to connect to (e.g., `${APP_NAME}-postgresql`).
- `POSTGRES_USER`: The application's database user.
- `POSTGRES_DB`: The name of the application's database.
- `POSTGRES_PASSWORD_FILE`: The path inside the container to the file containing the user password.

### Secrets

This service uses the same `POSTGRES_PASSWORD` secret as the `postgresql` service, which is mounted into the container.

## Usage

This service is not intended to be included in the regular `x-required-services` list. To perform a restore, you should run this service manually using `docker compose up`.

1.  Place the backup file you want to restore into the `./restore` directory. The script will look for the latest file in this directory.
2.  Run the restore service:
    ```bash
    docker compose -f docker-compose.main.yaml up postgresql_restore
    ```
3.  The service will start, execute the restore script, and then stop. Check the logs to ensure the restore was successful.
