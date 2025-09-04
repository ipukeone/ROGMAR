# VSCode Server Application

This directory contains the configuration for deploying `code-server`, a service that runs Visual Studio Code on a remote server, accessible through a browser. This setup allows you to develop from anywhere on any device.

## Application Overview

This `code-server` deployment is composed of two services:

- **app:** The main `code-server` application.
- **socketproxy:** A secure proxy for the Docker socket. This is included to allow `code-server` to interact with the Docker daemon (e.g., for building and managing containers) without exposing the main Docker socket directly to the development environment.

## How to Use

1.  **Run the Setup Script:** From the root of the repository, run the `run.sh` script and point it to this directory:
    ```bash
    ./run.sh VSCode
    ```
    This will:
    - Clone the required `socketproxy` service template.
    - Merge the `docker-compose.app.yaml` and `docker-compose.socketproxy.yaml` files into a single `docker-compose.main.yaml`.
    - Consolidate all `.env` variables into a single `.env` file in this directory.

2.  **Configure `.env`:** Review and edit the generated `.env` file.
    - Set `TRAEFIK_HOST` to the domain you want to use for `code-server`.
    - Set `LOCAL_PATH` to the directory on your host machine that you want to open as the default workspace in `code-server`.

3.  **Deploy:** Start the application stack using Docker Compose:
    ```bash
    docker compose -f docker-compose.main.yaml up -d
    ```

## Configuration

### Environment Variables

The following environment variables can be configured in the `VSCode/.env` file:

- `IMAGE`: The Docker image for `code-server`.
  - **Default:** `lscr.io/linuxserver/code-server`
- `APP_NAME`: The base name for the containers and services.
  - **Default:** `vscode`
- `TRAEFIK_HOST`: The Traefik router rule for exposing `code-server`.
  - **Example:** ``Host(`vscode.your-domain.com`)``
- `TRAEFIK_PORT`: The internal port that `code-server` listens on.
  - **Default:** `8443`
- `LOCAL_PATH`: The local directory on the host machine to mount as the main workspace.
  - **Example:** `/path/to/your/projects`
- `DOCKER_MODS`: LinuxServer.io Docker mods to install additional functionality. This configuration includes a mod to install the Docker CLI.
  - **Default:** `linuxserver/mods:universal-docker`

### Socket Proxy Permissions

This application enables broad permissions on the `socketproxy` to allow for full Docker management from within the `code-server` environment. The following permissions are enabled by default in the `.env` file: `CONTAINERS`, `IMAGES`, `INFO`, `NETWORKS`, `SERVICES`, `TASKS`, `VOLUMES`, and `POST` (full write access).

**Warning:** Granting these permissions to a web-accessible development environment has significant security implications. Ensure that you have strong authentication (e.g., via the `authentik-proxy` middleware) in front of this service.

### Required Templates

This application requires the following service template:

- `socketproxy`
