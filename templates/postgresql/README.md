# PostgreSQL Service

This template provides a standardized configuration for a PostgreSQL database service. PostgreSQL is a powerful, open-source object-relational database system.

## Service Overview

- **Image:** The Docker image for the service is specified by the `POSTGRES_IMAGE` variable.
- **Networking:** The service connects to the `backend` network to allow application services to communicate with it.
- **Data Persistence:** The database data is stored in a Docker volume named `database`, which is mounted at `/var/lib/postgresql/data`.
- **Initialization:** An optional `init.sql` script can be placed in the `./scripts/` directory to perform initial database setup.
- **Healthcheck:** A healthcheck is configured to ensure the PostgreSQL server is ready to accept connections.

## Configuration

### Environment Variables

This template uses the following environment variables, which can be configured in the `.env` file:

#### Container Basics
- `POSTGRES_IMAGE`: The Docker image to use for the PostgreSQL service.
  - **Default:** `postgres:17-alpine`

#### Filesystem & Secrets
- `POSTGRES_PASSWORD_PATH`: The path on the host machine where the secret file is stored.
  - **Default:** `./secrets/`
- `POSTGRES_PASSWORD_FILENAME`: The name of the file containing the PostgreSQL user password.
  - **Default:** `POSTGRES_PASSWORD`

The following environment variables are set directly in the `docker-compose.postgresql.yaml` file:

- `POSTGRES_USER`: The username for the database. This is automatically set to the value of `${APP_NAME}`.
- `POSTGRES_DB`: The name of the database to be created. This is also set to the value of `${APP_NAME}`.
- `POSTGRES_PASSWORD_FILE`: The path inside the container to the file containing the user password.

### Secrets

This service requires one secret:

- `POSTGRES_PASSWORD`: The password for the application user.

This secret must be placed in a file within the directory specified by `POSTGRES_PASSWORD_PATH`.

## Usage

To use this template, include `postgresql` in the `x-required-services` list of your main application's `docker-compose.app.yaml` file. The application service should then be configured to connect to the database using the hostname `${APP_NAME}-postgresql` and the credentials defined here.
