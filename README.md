# mathtrail-infra
Global cluster infrastructure — deploys Vault, External Secrets, and shared security components.

## What This Repo Deploys
- **Vault** — secrets management (dynamic DB credentials, KV secrets)
- **External Secrets Operator** — sync Vault secrets to Kubernetes

## Tech Stack
- **Orchestration**: Helm, ArgoCD
- **Secrets**: Vault, External Secrets
- **Task Runner**: Just

## Repository Structure
```
apps/                   # one folder per ArgoCD Application (self-contained Helm charts)
manifests/              # raw K8s YAML (namespaces, RBAC, Jobs, SecretStores)
justfile                # deploy / delete recipes
platform.env            # platform-wide constants
```

## Prerequisites

### Required on Host
- **Docker** — container runtime

See the [core repository](../core/README.md) for complete setup instructions.

### Included in DevContainer
- **Helm** — Kubernetes package manager
- **kubectl** — Kubernetes command-line tool
- **Just** — task runner for common commands

## Usage
```sh
just deploy    # Deploy Vault + namespace + components
just delete    # Remove everything
```

## DevContainer Support
A DevContainer configuration is included. Inside the container: kubectl, Helm, Docker CLI, Just.

## Troubleshooting
- Check cluster connectivity: `kubectl cluster-info`
- Verify Vault: `kubectl get pods -n vault`
- Verify namespace: `kubectl get ns mathtrail`
