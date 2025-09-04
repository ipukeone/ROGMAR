# Redis Service

This template provides a configuration for a Redis service. Redis is an in-memory data structure store, used as a database, cache, and message broker.

## Service Overview

- **Image:** The Docker image for the service is specified by the `REDIS_IMAGE` variable.
- **Networking:** The service connects to the `backend` network.
- **Data Persistence:** Data is stored in a Docker volume named `redis`, which is mounted at `/data`. The `save 60 1` command ensures that the dataset is saved to disk at least every 60 seconds if at least 1 key has changed.
- **Security:** The service is configured to require a password for all commands.
- **Healthcheck:** A healthcheck is configured to ping the Redis server and ensure it responds with `PONG`.

## Configuration

### Environment Variables

This template uses the following environment variables, which can be configured in the `.env` file:

#### Container Basics
- `REDIS_IMAGE`: The Docker image to use for the Redis service.
  - **Default:** `docker.io/library/redis:alpine`

#### Filesystem & Secrets
- `REDIS_PASSWORD_PATH`: The path on the host machine where the secret file is stored.
  - **Default:** `./secrets/`
- `REDIS_PASSWORD_FILENAME`: The name of the file containing the Redis password.
  - **Default:** `REDIS_PASSWORD`

### Secrets

This service requires one secret:

- `REDIS_PASSWORD`: The password for the Redis instance.

This secret must be placed in a file within the directory specified by `REDIS_PASSWORD_PATH`. The password is read from the file `/run/secrets/REDIS_PASSWORD` inside the container and passed to the `redis-server` command.

## Usage

To use this template, include `redis` in the `x-required-services` list of your main application's `docker-compose.app.yaml` file. The application service should then be configured to connect to Redis using the hostname `${APP_NAME}-redis` and the password provided in the secret.
