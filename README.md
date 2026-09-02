# DevOps Server Stack

A pragmatic, quick-start DevOps management server.

## Quick Start

### 1. Install Go Task (on Ubuntu)
Task is the automation runner for this repo.
```bash
## for Debian-based:
curl -1sLf 'https://dl.cloudsmith.io/public/task/task/setup.deb.sh' | sudo -E bash
apt install task

## for other OS-es see https://taskfile.dev/docs/installation
```

### 2. Environment Setup
Copy the example environment file and update your secrets:
```bash
cp .env.example .env
nano .env
```

### 3. Deploy
```bash
task up
```

## Operations
- `task up` - Start the stack
- `task down` - Stop the stack
- `task logs` - View logs
- `task vault-init` - Initialize Vault (first run only)

## Semaphore host management

See [Semaphore host-management prerequisites](docs/semaphore-host-prerequisites.md) for Windows WinRM/NTLM and Linux password-auth support.

Verify the running image with:

```bash
task semaphore:prereqs
```

## Database upgrades

See [PostgreSQL 15 to 18 migration](docs/postgres-15-to-18.md) before deploying the PostgreSQL 18 image over an existing installation.

## Components
- **HashiCorp Vault**: Central secret management.
- **Ansible + Semaphore**: Infrastructure orchestration and automation.
- **Nginx Proxy Manager**: Reverse proxy and SSL management.
- **Portainer**: Container management UI.
- **Wiki.js**: Git-backed documentation hub.
