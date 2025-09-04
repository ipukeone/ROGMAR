# PostgreSQL Backup Service

This template provides a service for performing periodic backups of a PostgreSQL database. It uses `pg_dump` to create a compressed SQL dump of the database at a configurable interval.

## Service Overview

- **Image:** The Docker image for the service is specified by the `POSTGRES_IMAGE` variable, which should be the same as the main PostgreSQL service.
- **Networking:** The service connects to the `backend` network to communicate with the `postgresql` service.
- **Volumes:** It mounts a local `./backup` directory for storing the backup files.
- **Scripts:** The core logic is contained within the `scripts/backup-cron.sh` script, which is executed by the container's entrypoint.
- **Dependencies:** This service depends on the `postgresql` service being healthy before it starts.

## Configuration

### Environment Variables

This template uses the following environment variables, which can be configured in the `.env` file:

- `POSTGRES_BACKUP_INTERVAL_HOURS`: The interval in hours at which to perform a backup.
  - **Default:** `2`
- `POSTGRES_BACKUP_KEEP`: The number of recent backups to keep. Older backups will be deleted.
  - **Default:** `5`

The following environment variables are passed from the main application's environment:

- `DB_HOST`: The hostname of the PostgreSQL service to connect to (e.g., `${APP_NAME}-postgresql`).
- `POSTGRES_USER`: The application's database user.
- `POSTGRES_DB`: The name of the application's database.
- `POSTGRES_PASSWORD_FILE`: The path inside the container to the file containing the user password.

### Secrets

This service uses the same `POSTGRES_PASSWORD` secret as the `postgresql` service, which is mounted into the container.

## Usage

To use this template, include `postgresql_backup` in the `x-required-services` list of your main application's `docker-compose.app.yaml` file. Ensure that the `postgresql` service is also included and properly configured.

### Restore Instructions

To restore a backup, you can use the `pg_restore` command or simply decompress the dump and pipe it to `psql`.

Example command:

```bash
# Unzip and import the dump into the target database
gunzip -c /path/to/your/backup/file.sql.gz | psql -h <host> -U <user> -d <db>
```
