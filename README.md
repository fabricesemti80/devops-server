# DevOps Server Stack

A pragmatic, quick-start DevOps management server.

## Quick Start

### 1. Install Go Task (on Ubuntu)
Task is the automation runner for this repo.
```bash
sh -c "$(curl -sL https://taskfile.dev/install.sh)"
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

## Components
- **HashiCorp Vault**: Central secret management.
- **Ansible + Semaphore**: Infrastructure orchestration and automation.
- **Nginx Proxy Manager**: Reverse proxy and SSL management.
- **Portainer**: Container management UI.
- **Wiki.js**: Git-backed documentation hub.
