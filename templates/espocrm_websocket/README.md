# EspoCRM WebSocket Service

This template provides the configuration for the EspoCRM WebSocket service. This service enables real-time notifications and updates within the EspoCRM application, such as instant messages, alerts, and live record updates.

## Service Overview

- **Image:** The Docker image for the service is specified by the `${IMAGE}` variable, which must be defined in the main `.env` file.
- **Networking:** The WebSocket service connects to the `backend` network and is exposed via Traefik on the path `/ws`.
- **Entrypoint:** The service uses a custom entrypoint `docker-websocket.sh` to start the WebSocket server.
- **Dependencies:** This service depends on the `mariadb` and the main `app` services being healthy before it starts.

## Configuration

### Environment Variables

This service is configured with the following environment variables, which are set directly in the `docker-compose.espocrm_websocket.yaml` file:

- `ESPOCRM_CONFIG_USE_WEB_SOCKET`: Set to `"true"` to enable WebSocket functionality in EspoCRM.
- `ESPOCRM_CONFIG_WEB_SOCKET_ZERO_M_Q_SUBSCRIBER_DSN`: The ZeroMQ subscriber Data Source Name (DSN), configured to listen on all interfaces on port `7777`.
- `ESPOCRM_CONFIG_WEB_SOCKET_ZERO_M_Q_SUBMISSION_DSN`: The ZeroMQ submission DSN, configured to connect to itself (`${APP_NAME}-websocket`) on port `7777`.

### Volumes

The service mounts a set of common volumes defined by the `*espocrm_common_volumes` YAML anchor. This ensures that the WebSocket server has access to the same application files and data as the main EspoCRM service.

### Secrets

This template does not directly use any secrets.

## Usage

To use this template, include `espocrm_websocket` in the `x-required-services` list of your main EspoCRM application's `docker-compose.app.yaml` file. The Traefik labels will automatically configure the reverse proxy to route WebSocket traffic to this service.
