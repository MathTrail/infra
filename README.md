# mathtrail-infra
Global cluster infrastructure — deploys Dapr runtime and shared Dapr components.

## What This Repo Deploys
- **Dapr runtime** — Helm chart into `dapr-system` namespace
- **Dapr components** — shared components (statestore) into the application namespace

## Tech Stack
- **Orchestration**: Helm, Skaffold
- **Service Mesh**: Dapr
- **Task Runner**: Just

## Repository Structure
```
dapr/
  components.yaml     # shared Dapr components (statestore)
skaffold.yaml         # Skaffold config (module: mathtrail-infra)
justfile              # deploy / delete recipes
```

## Prerequisites

### Required on Host
- **Docker** — container runtime

See the [core repository](../core/README.md) for complete setup instructions.

### Included in DevContainer
- **Helm** — Kubernetes package manager
- **kubectl** — Kubernetes command-line tool
- **Dapr CLI** — Dapr runtime CLI
- **Just** — task runner for common commands

## Usage
```sh
just deploy    # Deploy Dapr + namespace + components
just delete    # Remove everything
```

## DevContainer Support
A DevContainer configuration is included. Inside the container: kubectl, Helm, Docker CLI, Dapr CLI, Just.

## Troubleshooting
- Check cluster connectivity: `kubectl cluster-info`
- Verify Dapr: `kubectl get pods -n dapr-system`
- Verify namespace: `kubectl get ns mathtrail`
