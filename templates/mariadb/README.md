# MariaDB Service

This template provides a standardized and optimized configuration for a MariaDB database service. MariaDB is a popular open-source relational database, forked from MySQL.

## Service Overview

- **Image:** The Docker image for the service is specified by the `MARIADB_IMAGE` variable.
- **Networking:** The service connects to the `backend` network to allow application services to communicate with it.
- **Data Persistence:** The database data is stored in a Docker volume named `database`, which is mounted at `/var/lib/mysql`.
- **Healthcheck:** A healthcheck is configured to ensure the MariaDB server is running and the InnoDB engine is initialized.

## Configuration

### Environment Variables

This template uses the following environment variables, which can be configured in the `.env` file:

#### Container Basics
- `MARIADB_IMAGE`: The Docker image to use for the MariaDB service.
  - **Default:** `mariadb:lts`

#### Filesystem & Secrets
- `MARIADB_PASSWORD_PATH`: The path on the host machine where the secret files are stored.
  - **Default:** `./secrets/`
- `MARIADB_PASSWORD_FILENAME`: The name of the file containing the MariaDB user password.
  - **Default:** `MARIADB_PASSWORD`
- `MARIADB_ROOT_PASSWORD_PATH`: The path on the host machine where the root secret file is stored.
  - **Default:** `./secrets/`
- `MARIADB_ROOT_PASSWORD_FILENAME`: The name of the file containing the MariaDB root password.
  - **Default:** `MARIADB_ROOT_PASSWORD`

#### MySQL Server Configuration
These variables are passed as command-line arguments to the MariaDB server to tune its performance.

- `MARIADB_INNODB_LOG_FILE_SIZE`: The size of the InnoDB log file.
  - **Default:** `256M`
- `MARIADB_INNODB_BUFFER_POOL_SIZE`: The size of the InnoDB buffer pool. It is recommended to set this to about 70% of the container's available RAM.
  - **Default:** `2G`
- `MARIADB_SORT_BUFFER_SIZE`: The sort buffer size, which affects `ORDER BY` and `GROUP BY` performance.
  - **Default:** `2M`
- `MARIADB_MAX_ALLOWED_PACKET`: The maximum allowed packet size for client-server communication.
  - **Default:** `64M`
- `MARIADB_INNODB_IO_CAPACITY`: The number of I/O operations per second (IOPS) that the storage system can handle. This should be set higher for SSDs/NVMe.
  - **Default:** `1000`

The following environment variables are set directly in the `docker-compose.mariadb.yaml` file:

- `MARIADB_USER`: The username for the database. This is automatically set to the value of `${APP_NAME}`.
- `MARIADB_DATABASE`: The name of the database to be created. This is also set to the value of `${APP_NAME}`.
- `MARIADB_AUTO_UPGRADE`: When set to `true`, it allows the database to be automatically upgraded if a newer version of MariaDB is used.
- `MARIADB_PASSWORD_FILE`: The path inside the container to the file containing the user password.
- `MARIADB_ROOT_PASSWORD_FILE`: The path inside the container to the file containing the root password.

### Secrets

This service requires two secrets:

- `MARIADB_PASSWORD`: The password for the application user.
- `MARIADB_ROOT_PASSWORD`: The password for the MariaDB root user.

These secrets must be placed in files within the directory specified by `MARIADB_PASSWORD_PATH` and `MARIADB_ROOT_PASSWORD_PATH`.

## Usage

To use this template, include `mariadb` in the `x-required-services` list of your main application's `docker-compose.app.yaml` file. The application service should then be configured to connect to the database using the hostname `${APP_NAME}-mariadb` and the credentials defined here.
