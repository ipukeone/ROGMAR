# Traefik Application

This directory contains the configuration for deploying Traefik, a modern reverse proxy and load balancer that makes deploying microservices easy. This setup is configured to be the main entrypoint for all other services, providing automatic SSL certificate generation via Let's Encrypt and Cloudflare.

## Application Overview

This Traefik deployment is composed of several services working together:

- **app:** The main Traefik reverse proxy service.
- **socketproxy:** A secure proxy for the Docker socket, allowing Traefik to discover other containers without direct access to the Docker daemon.
- **traefik_certs-dumper:** A service that extracts generated SSL certificates from Traefik's `acme.json` file and can copy them to other locations.

## How to Use

1.  **Run the Setup Script:** From the root of the repository, run the `run.sh` script and point it to this directory:
    ```bash
    ./run.sh Traefik
    ```
    This will:
    - Clone the required service templates (`socketproxy`, `traefik_certs-dumper`).
    - Merge all `docker-compose.*.yaml` files into a single `docker-compose.main.yaml`.
    - Consolidate all `.env` variables into a single `.env` file in this directory.
    - Copy required secret files and configuration files.

2.  **Configure `.env`:** Review and edit the generated `.env` file. You must configure the following:
    - `TRAEFIK_HOST`: The domain for the Traefik dashboard.
    - `TRAEFIK_DOMAIN`: Your primary domain name (e.g., `example.com`).
    - `EMAIL_PREFIX`: The prefix for the email address used for Let's Encrypt registration.

3.  **Provide Secrets:** Edit the `secrets/CF_DNS_API_TOKEN` file to provide your Cloudflare API token. This is required for the DNS-01 challenge to obtain wildcard SSL certificates.

4.  **Configure Middlewares and TLS:** Edit the `appdata/config/middlewares.yaml` and `appdata/config/tls-opts.yaml` files to define your global security headers, rate limits, and TLS options.

5.  **Deploy:** Start the application stack using Docker Compose:
    ```bash
    docker compose -f docker-compose.main.yaml up -d
    ```

## Configuration

### Environment Variables

The following environment variables can be configured in the `Traefik/.env` file:

- `IMAGE`: The Docker image for the Traefik service.
  - **Default:** `traefik`
- `APP_NAME`: The base name for the containers and services.
  - **Default:** `traefik`
- `TRAEFIK_HOST`: The Traefik router rule for exposing the dashboard.
  - **Example:** ``Host(`traefik.your-domain.com`)``
- `TRAEFIK_DOMAIN`: The root domain that Traefik will manage certificates for.
  - **Example:** `your-domain.com`
- `TRAEFIK_PORT`: The internal port for the Traefik dashboard.
  - **Default:** `8080`
- `CF_DNS_API_TOKEN_PATH`: Path to the directory containing the Cloudflare API token secret.
  - **Default:** `./secrets/`
- `CF_DNS_API_TOKEN_FILENAME`: Filename of the Cloudflare API token secret.
  - **Default:** `CF_DNS_API_TOKEN`
- `LOG_LEVEL`: The logging level for Traefik.
  - **Default:** `ERROR`
- `EMAIL_PREFIX`: The email prefix for Let's Encrypt.
  - **Default:** `admin`
- `CERTRESOLVER`: The certificate resolver to use (configured for Cloudflare).
  - **Default:** `cloudflare`
- `AUTHENTIK_CONTAINER_NAME`: The name of the Authentik container, used for the Authentik middleware.
  - **Default:** `authentik`

### Required Templates

This application requires the following service templates:

- `socketproxy`
- `traefik_certs-dumper`

### Networks

This application creates two external networks:

- `frontend`: For public-facing services.
- `backend`: For internal communication between services.

Ensure these networks are created before deploying other applications that will be managed by Traefik.
```bash
docker network create frontend
docker network create backend
```
