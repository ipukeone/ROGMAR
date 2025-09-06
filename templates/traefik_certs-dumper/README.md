# Traefik Certs Dumper Service

This template provides a service that automatically extracts SSL certificates from a Traefik `acme.json` file and saves them as individual `.pem` files. It can also execute a post-hook script after certificates are dumped, for example, to copy them to another server.

## Service Overview

- **Image:** This service builds a custom Docker image using the `dockerfiles/dockerfile.traefik-certs-dumper.scp` Dockerfile, which includes `traefik-certs-dumper` and `openssh-client` (for `scp`).
- **Networking:** The service connects to the `backend` network.
- **Volumes:**
    - It mounts the Traefik `acme.json` file from `./appdata/config/certs/` into the container at `/data/`.
    - It mounts a `post-hook.sh` script from `./scripts/` into the container at `/config/post-hook.sh`.
    - It mounts the SSH private key from `/root/.ssh/id_rsa` on the host to `/root/.ssh/id_rsa` in the container for `scp` operations.
- **Entrypoint:** The service has a custom entrypoint that waits for the `acme.json` file to be populated with certificates and then runs the `traefik-certs-dumper` tool in watch mode.
- **Dependencies:** This service depends on the main `app` service (presumably Traefik) being healthy before it starts.

## Configuration

This template does not use any environment variables from a `.env` file. Its behavior is configured through the `entrypoint` and the mounted volumes.

### `acme.json`

The service expects to find Traefik's `acme.json` file in the `./appdata/config/certs/` directory relative to the application's root. This file is where Traefik stores the Let's Encrypt certificates it obtains.

### `post-hook.sh`

A script named `post-hook.sh` must be placed in the `./scripts/` directory. This script is executed every time the `traefik-certs-dumper` successfully dumps the certificates. It can be used to perform actions like copying the certificates to a remote server.

**Example `post-hook.sh`:**

```bash
#!/bin/sh
#
# This script copies the dumped certificate files to a remote server.
#
echo "Executing post-hook: Copying certs to remote server..."
scp -o StrictHostKeyChecking=no -r /data/files/* user@remote-server:/path/to/certs/
echo "Post-hook finished."
```

### SSH Key

To use the `scp` functionality in the post-hook script, you must mount your SSH private key into the container. The `docker-compose.traefik_certs_dumper.yaml` is configured to mount `/root/.ssh/id_rsa` from the host.

## Usage

To use this template, include `traefik_certs-dumper` in the `x-required-services` list of your main Traefik application's `docker-compose.app.yaml` file. Ensure that the volume paths for the `acme.json` file and the `post-hook.sh` script are correct for your setup.
