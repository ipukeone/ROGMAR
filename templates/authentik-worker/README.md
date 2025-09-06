# Authentik Worker Service

This template provides the configuration for an Authentik worker service. Authentik is a flexible and powerful open-source Identity Provider (IdP). The worker component is responsible for handling background tasks, such as sending emails, running outpost integrations, and other asynchronous jobs.

## Service Overview

- **Image:** The Docker image for the service is specified by the `${IMAGE}` variable, which must be defined in the main `.env` file.
- **Networking:** The worker connects to the `backend` network to communicate with other services like PostgreSQL and Redis.
- **Dependencies:** This service depends on `postgresql` and `redis` being healthy before it starts.

## Configuration

### Environment Variables

This template does not define any environment variables in its own `.env` file. All required environment variables are expected to be provided by the main application's configuration, which are then passed to the worker via a YAML anchor (`*authentik_common_environment`).

A typical Authentik setup requires the following variables:

- `AUTHENTIK_POSTGRESQL__HOST`: The hostname of the PostgreSQL database.
- `AUTHENTIK_POSTGRESQL__USER`: The username for the PostgreSQL database.
- `AUTHENTIK_POSTGRESQL__NAME`: The name of the PostgreSQL database.
- `AUTHENTIK_POSTGRESQL__PORT`: The port of the PostgreSQL database.
- `AUTHENTIK_REDIS__HOST`: The hostname of the Redis instance.
- `AUTHENTIK_REDIS__PORT`: The port of the Redis instance.
- `AUTHENTIK_SECRET_KEY`: A secret key for the Authentik instance.

### Secrets

This service requires the following secrets to be defined and mounted:

- `POSTGRES_PASSWORD`: The password for the PostgreSQL database. The path to this secret is constructed from `${POSTGRES_PASSWORD_PATH}` and `${POSTGRES_PASSWORD_FILENAME}`.
- `REDIS_PASSWORD`: The password for the Redis instance. The path to this secret is constructed from `${REDIS_PASSWORD_PATH}` and `${REDIS_PASSWORD_FILENAME}`.
- `AUTHENTIK_SECRET_KEY_PASSWORD`: The password for the Authentik secret key. The path to this secret is constructed from `${AUTHENTIK_SECRET_KEY_PASSWORD_PATH}` and `${AUTHENTIK_SECRET_KEY_PASSWORD_FILENAME}`.

## Usage

To use this template, include `authentik-worker` in the `x-required-services` list of your main application's `docker-compose.app.yaml` file. Ensure that all required environment variables and secrets are properly defined in your main configuration.
