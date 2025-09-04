# EspoCRM Daemon Service

This template provides the configuration for the EspoCRM daemon service. EspoCRM is a powerful open-source Customer Relationship Management (CRM) application. The daemon is a background process required for certain EspoCRM functionalities, such as running scheduled jobs and workflows.

## Service Overview

- **Image:** The Docker image for the service is specified by the `${IMAGE}` variable, which must be defined in the main `.env` file.
- **Networking:** The daemon connects to the `backend` network to communicate with the main EspoCRM application and the database.
- **Entrypoint:** The service uses a custom entrypoint `docker-daemon.sh` to start the daemon process.
- **Dependencies:** This service depends on the `mariadb` and the main `app` services being healthy before it starts.

## Configuration

### Environment Variables

This template does not define any environment variables in its own `.env` file. All required environment variables are expected to be provided by the main EspoCRM application's configuration.

### Volumes

The service mounts a set of common volumes defined by the `*espocrm_common_volumes` YAML anchor. This ensures that the daemon has access to the same application files and data as the main EspoCRM service.

### Secrets

This template does not directly use any secrets, but it operates in an environment where the main application manages database credentials and other sensitive data.

## Usage

To use this template, include `espocrm_daemon` in the `x-required-services` list of your main EspoCRM application's `docker-compose.app.yaml` file. Ensure that the main application provides the necessary configurations and that the `mariadb` and `app` services are correctly defined.
