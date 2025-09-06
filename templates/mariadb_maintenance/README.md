# MariaDB Maintenance Service

This template provides a service for performing maintenance tasks on a MariaDB database, primarily focused on creating and managing backups. It uses `mariadb-backup` for full/incremental backups and `mysqldump` for logical SQL dumps. The backup schedule is managed by `supercronic`.

## Service Overview

- **Image:** This service builds a custom Docker image using the `dockerfiles/dockerfile.supersonic.mariadb` Dockerfile.
- **Networking:** The service connects to the `backend` network to communicate with the `mariadb` service.
- **Volumes:** It mounts the `database` volume from the `mariadb` service to perform backups, and also mounts local `./backup` and `./restore` directories for storing and retrieving backup files.
- **Scripts:** The core logic is contained within the `scripts/backup.sh` and `scripts/docker-entrypoint.sh` scripts. The schedule is defined in `scripts/backup.cron`.

## Configuration

### Environment Variables

This template uses the following environment variables, which can be configured in the `.env` file:

- `MARIADB_BACKUP_RETENTION_DAYS`: The number of days to keep backups. Older backups will be deleted.
  - **Default:** `7`
- `MARIADB_BACKUP_DEBUG`: Set to `true` to enable debug mode for the backup script.
  - **Default:** `false`
- `MARIADB_RESTORE_DRY_RUN`: If set to `true`, the restore script will simulate a restore without actually copying any data.
  - **Default:** `false`
- `MARIADB_RESTORE_DEBUG`: Set to `true` to enable debug mode for the restore script.
  - **Default:** `false`

The following environment variables are passed from the main application's environment:

- `MARIADB_DB_HOST`: The hostname of the MariaDB service to connect to (e.g., `${APP_NAME}-mariadb`).
- `MARIADB_USER`: The application's database user.
- `MARIADB_DATABASE`: The name of the application's database.
- `MARIADB_PASSWORD_FILE`: The path inside the container to the file containing the user password.
- `MARIADB_ROOT_PASSWORD_FILE`: The path inside the container to the file containing the root password.

### Secrets

This service uses the same `MARIADB_PASSWORD` and `MARIADB_ROOT_PASSWORD` secrets as the `mariadb` service, which are mounted into the container via a YAML anchor.

### Cron Schedule (`backup.cron`)

The backup schedule is defined in `scripts/backup.cron` and managed by `supercronic`. You can edit this file to change the frequency and type of backups. The default schedule is:

```cron
# Minute Hour DayOfMonth Month DayOfWeek Command
0 2 * * * /scripts/backup.sh full
0 3 * * * /scripts/backup.sh incremental
0 4 * * 0 /scripts/backup.sh dump
```

- A **full** backup is performed daily at 2:00 AM.
- An **incremental** backup is performed daily at 3:00 AM.
- A **dump** (SQL) backup is performed weekly on Sunday at 4:00 AM.

## Usage

To use this template, include `mariadb_maintenance` in the `x-required-services` list of your main application's `docker-compose.app.yaml` file. Ensure that the `mariadb` service is also included and properly configured.

### Restore Instructions

#### Full / Incremental Backup

1.  Prepare the backup using `mariadb-backup --prepare`. This makes the backup consistent and ready for restoration.
2.  If you are using incremental backups, you must apply each incremental backup in sequence to the full backup.
3.  Restore the prepared backup by copying the files back to the MariaDB data directory.

Example commands (run inside the maintenance container):

```bash
# Prepare a full backup
mariadb-backup --prepare --target-dir=/backup/full/YYYYMMDD_HHMMSS

# Apply an incremental backup to the prepared full backup
mariadb-backup --prepare --target-dir=/backup/full/YYYYMMDD_HHMMSS --incremental-dir=/backup/incremental/YYYYMMDD_HHMMSS
```

#### SQL Dump

You can restore an SQL dump by importing the `.sql.gz` file into the database.

```bash
# Unzip and import the dump into the target database
gunzip -c /backup/dumps/mariadb_dump_YYYYMMDD_HHMMSS.sql.gz | mariadb -h <host> -u <user> -p <db>
```
