# DevOps Server Stack

A pragmatic, quick-start DevOps management server.

## Components
- **HashiCorp Vault**: Central secret management.
- **Ansible + Semaphore**: Infrastructure orchestration and automation.
- **Nginx Proxy Manager**: Reverse proxy and SSL management.
- **Portainer**: Container management UI.

## Architecture Note
The goal is to minimize environment variables in the Compose files. Vault is the root of trust. While Docker Compose doesn't natively "pull" secrets from Vault at runtime without a sidecar or init-container (like Vault Agent), this setup provides the foundation for using Vault as the source of truth.

## Getting Started
1. `docker compose -f docker-compose.yml up -d`
2. Initialize Vault: `docker exec vault vault operator init`
3. Save the unseal keys and root token.
