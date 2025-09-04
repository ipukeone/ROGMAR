# Socket Proxy Service

This template provides a configuration for a Docker socket proxy service. This service acts as a secure intermediary, allowing other containers to access the Docker API without directly exposing the main Docker socket (`/var/run/docker.sock`). This is a critical security practice to prevent container breakouts.

The proxy is configured with a fine-grained permission system, allowing you to control exactly which Docker API endpoints are accessible.

## Service Overview

- **Image:** The Docker image for the service is specified by the `SOCKETPROXY_IMAGE` variable.
- **Networking:** The service connects to the `backend` network.
- **Volumes:** It mounts the host's Docker socket (`/var/run/docker.sock`) in read-only mode.

## Configuration

### Environment Variables

This template uses the following environment variables, which can be configured in the `.env` file, to control access to the Docker API. A value of `1` enables access, and `0` disables it.

#### Container Basics
- `SOCKETPROXY_IMAGE`: The Docker image to use for the socket proxy service.
  - **Default:** `lscr.io/linuxserver/socket-proxy`

#### General
- `SOCKETPROXY_LOG_LEVEL`: Sets the log level for the proxy.
  - **Default:** `err`

#### Docker API Permissions (Read)
- `SOCKETPROXY_EVENTS`: Access to `/events` (real-time Docker event stream).
  - **Default:** `1`
- `SOCKETPROXY_PING`: Access to `/_ping` (basic health check of Docker API).
  - **Default:** `1`
- `SOCKETPROXY_VERSION`: Access to `/version` (Docker Engine version info).
  - **Default:** `1`
- `SOCKETPROXY_AUTH`: Access to `/auth`.
  - **Default:** `0`
- `SOCKETPROXY_BUILD`: Access to `/build`.
  - **Default:** `0`
- `SOCKETPROXY_COMMIT`: Access to `/commit`.
  - **Default:** `0`
- `SOCKETPROXY_CONFIGS`: Access to `/configs` (Swarm configs).
  - **Default:** `0`
- `SOCKETPROXY_CONTAINERS`: Access to `/containers`.
  - **Default:** `0`
- `SOCKETPROXY_DISTRIBUTION`: Access to `/distribution`.
  - **Default:** `0`
- `SOCKETPROXY_EXEC`: Access to `/exec`.
  - **Default:** `0`
- `SOCKETPROXY_IMAGES`: Access to `/images`.
  - **Default:** `0`
- `SOCKETPROXY_INFO`: Access to `/info`.
  - **Default:** `0`
- `SOCKETPROXY_NETWORKS`: Access to `/networks`.
  - **Default:** `0`
- `SOCKETPROXY_NODES`: Access to `/nodes` (Swarm nodes).
  - **Default:** `0`
- `SOCKETPROXY_PLUGINS`: Access to `/plugins`.
  - **Default:** `0`
- `SOCKETPROXY_SECRETS`: Access to `/secrets` (Swarm secrets).
  - **Default:** `0`
- `SOCKETPROXY_SERVICES`: Access to `/services` (Swarm services).
  - **Default:** `0`
- `SOCKETPROXY_SESSION`: Access to `/session`.
  - **Default:** `0`
- `SOCKETPROXY_SWARM`: Access to `/swarm`.
  - **Default:** `0`
- `SOCKETPROXY_SYSTEM`: Access to `/system`.
  - **Default:** `0`
- `SOCKETPROXY_TASKS`: Access to `/tasks` (Swarm tasks).
  - **Default:** `0`
- `SOCKETPROXY_VOLUMES`: Access to `/volumes`.
  - **Default:** `0`

#### Global Write Permissions
- `SOCKETPROXY_POST`: Globally allows `POST`/`PUT`/`DELETE` requests. Set to `0` for read-only access.
  - **Default:** `0`

#### Fine-Grained Write Overrides
- `SOCKETPROXY_ALLOW_START`: Allows starting containers even if `SOCKETPROXY_POST=0`.
  - **Default:** `0`
- `SOCKETPROXY_ALLOW_STOP`: Allows stopping containers even if `SOCKETPROXY_POST=0`.
  - **Default:** `0`
- `SOCKETPROXY_ALLOW_RESTARTS`: Allows restarting containers even if `SOCKETPROXY_POST=0`.
  - **Default:** `0`

#### Miscellaneous
- `SOCKETPROXY_DISABLE_IPV6`: Disables IPv6 support inside the container.
  - **Default:** `1`

## Usage

To use this template, include `socketproxy` in the `x-required-services` list of your main application's `docker-compose.app.yaml` file. Any service that needs to interact with the Docker API (e.g., Traefik, Watchtower) should be configured to connect to `tcp://${APP_NAME}-socketproxy:2375` instead of using the host's Docker socket directly.
