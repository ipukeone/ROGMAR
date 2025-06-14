# MariaDB Backup Script

This script securely creates **full**, **incremental**, or **SQL dump** backups of a MariaDB instance.

---

## Usage

`backup.sh [full|incremental|dump]`

- `full` (default): Creates a full backup.
- `incremental`: Creates an incremental backup based on the last backup.
- `dump`: Creates an SQL dump of the specified database.

If no type is specified, `full` is used.

---

## Environment variables

| Variable                       | Required / Default         | Description                                        |
|---------------------------------|---------------------------|----------------------------------------------------|
| `MYSQL_DATABASE`                | **Required** (dump only)   | Name of the database to back up                    |
| `MYSQL_ROOT_PASSWORD_FILE`      | **Required**               | File containing the root password                  |
| `MYSQL_ROOT_USER`               | root                       | DB user for the backup                             |
| `MYSQL_DB_HOST`                 | mariadb                    | DB host                                            |
| `MYSQL_BACKUP_RETENTION_DAYS`   | 7                          | Number of days to keep backups                     |
| `MYSQL_BACKUP_COMPRESS_THREADS` | 4                          | Threads for compression                            |
| `MYSQL_BACKUP_PARALLEL`         | 4                          | Threads for parallel backup                        |
| `MYSQL_BACKUP_MIN_FREE_MB`      | 10240                      | Minimum free space required (MB)                   |
| `BACKUP_DIR`                    | /backup                    | Base directory for backups                         |

---

## Restore instructions

### Full / incremental backup

Backups can be prepared with `mariadb-backup --prepare` and restored via copy-back or manually:

# mariadb-backup --prepare --target-dir=/backup/full/20250614_01
# (run additional --prepare commands if using incremental backups)

### SQL dump

Import SQL dump:

# gunzip -c /backup/dumps/mariadb_dump_YYYYMMDD_HHMMSS.sql.gz | mariadb -h <host> -u <user> -p <db>

---

## Security

- `umask 077` ensures files are only readable by the owner.
- Passwords are never logged in plain text.
- Lockfile prevents concurrent runs.

---

## Failure conditions / checks

The script aborts if:

- There is not enough free disk space.
- The database is not reachable.
- The lockfile exists (a backup is already running).
- Required variables are missing.

---

## Cron usage

Recommended: run via **supercronic** and adjust the backup.cron to your needs:

```bash
# Minute Hour DayOfMonth Month DayOfWeek Command
0 2 * * * /path/to/backup.sh full
0 3 * * * /path/to/backup.sh incremental
0 4 * * 0 /path/to/backup.sh dump
```