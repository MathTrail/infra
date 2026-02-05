# mathtrail-infrastructure

Repository for deploying and managing the MathTrail platform infrastructure — includes environment setup, deployment scripts, and configuration for local and cloud environments.

## Prerequisites

Before you can deploy and manage the MathTrail infrastructure locally, ensure the following tools are installed **on your host machine**:

### Required on Host

- **Docker** — container runtime

See the [main MathTrail repository](../mathtrail/README.md) for complete setup instructions.

### Included in DevContainer

When you open this repository in the DevContainer, the following tools are automatically available:

- **Helm** — Kubernetes package manager
- **kubectl** — Kubernetes command-line tool
- **Dapr CLI** — Dapr runtime CLI
- **Just** — task runner for common commands

## Local Development Setup

### 1. Deploy Dapr

Deploy Dapr (Distributed Application Runtime) to your cluster:

```bash
just deploy
```

This will install Dapr system components into the `dapr-system` namespace.

## Available Commands

Check the [justfile](justfile) for all available commands. Common tasks:

- `just deploy` — Deploy Dapr to the cluster

## DevContainer Support

A DevContainer configuration is available for development within VS Code. Inside the container, you automatically get:

- **kubectl** — for managing Kubernetes clusters
- **Helm** — for deploying applications
- **Docker CLI** — for building and running container images
- **Dapr CLI** — for working with distributed application runtime
- **Just** — task runner for common commands

**Workflow:**

1. Open the workspace in DevContainer (click the "Dev Containers" button in VS Code)
2. Inside the container, use `kubectl`, `helm`, and `just deploy` to manage your cluster

## Troubleshooting

### Helm deployment fails

- Check cluster connectivity: `kubectl cluster-info`
- Verify namespaces: `kubectl get namespaces`
