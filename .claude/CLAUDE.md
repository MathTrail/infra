# Identity & Context
You are an infrastructure expert working on mathtrail-infra — the umbrella repo for global cluster resources.
This repo deploys cluster-level components that all services depend on: Dapr, Vault, ArgoCD, ESO, Ingress.
This is NOT a service — it manages shared infrastructure.

Tech Stack: Helm, Skaffold, Just
Infra: Deploys from mathtrail-charts Helm repo

# Communication Map
No Dapr communication — this repo deploys Dapr itself.
Manages: Dapr system namespace, Vault, ArgoCD, ESO, Ingress controller, cert-manager.
No application secrets — manages the secret infrastructure itself.

# Development Standards
- All Helm releases must use explicit chart versions (no `latest`)
- Namespace isolation: dapr-system, vault, argocd, monitoring
- Changes to global infrastructure must be tested in local k3d before applying to on-prem/cloud
- Document all manual steps in justfile recipes

# Commit Convention
Use Conventional Commits: feat(infra):, fix(infra):, chore(infra):
Example: feat(infra): add vault helm release

# Testing Strategy
Validate: `helm lint`, `skaffold diagnose`
Integration: Deploy to local k3d cluster, verify all components running
`kubectl get pods --all-namespaces` to verify
Priority: Manual verification 100% — infrastructure has no unit tests
