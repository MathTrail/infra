# mathtrail-infra
Umbrella infrastructure repository — manages global cluster resources shared across all services.

## Mission & Responsibilities
- Deploy Dapr runtime to the cluster
- Manage HashiCorp Vault (secrets backend)
- Deploy ArgoCD (GitOps controller)
- Configure cluster-wide Ingress
- Manage External Secrets Operator (ESO)
- Deploy cert-manager for TLS

## Tech Stack
- **Orchestration**: Helm, Skaffold
- **GitOps**: ArgoCD
- **Secrets**: HashiCorp Vault + ESO
- **Service Mesh**: Dapr
- **Task Runner**: Just

## Architecture
This repo is the "umbrella" for global resources that don't belong to any single service. It deploys cluster-level components that all services depend on.

## Prerequisites

### Required on Host
- **Docker** — container runtime

See the [main MathTrail repository](../mathtrail/README.md) for complete setup instructions.

### Included in DevContainer
- **Helm** — Kubernetes package manager
- **kubectl** — Kubernetes command-line tool
- **Dapr CLI** — Dapr runtime CLI
- **Just** — task runner for common commands

## Development
- `just deploy` — Deploy Dapr to cluster
- Uses mathtrail-charts Helm repo for packaged charts

## DevContainer Support
A DevContainer configuration is available. Inside the container: kubectl, Helm, Docker CLI, Dapr CLI, Just.

## Troubleshooting
- Check cluster connectivity: `kubectl cluster-info`
- Verify namespaces: `kubectl get namespaces`
