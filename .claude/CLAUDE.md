# Identity & Context
You are an infrastructure expert working on mathtrail-infra — the umbrella repo for global cluster resources.
This repo deploys cluster-level components that all services depend on (currently Dapr).
This is NOT a service — it manages shared infrastructure.

Tech Stack: Helm, Skaffold, Just
Infra: Deploys remote charts from mathtrail-charts Helm repo (https://MathTrail.github.io/charts/charts)

# Repo Layout
- `skaffold.yaml` — orchestrates deploy: Helm releases + raw manifests
- `skaffold.env` — platform constants shared across all MathTrail repos (namespace, registry, chart repo URL, cluster name)
- `justfile` — developer-facing recipes (`just deploy`, `just delete`)
- `dapr/` — raw Kubernetes manifests applied alongside Helm:
  - `namespace.yaml` — creates the `mathtrail` application namespace
  - `components.yaml` — Dapr component definitions (statestore, etc.)

# What Is Currently Deployed
- **Dapr** (Helm release into `dapr-system` namespace, from remote chart)
- **mathtrail namespace** (raw manifest)
- **Dapr in-memory statestore** component (raw manifest, applied to default namespace from skaffold.env)

Future candidates: Vault, ArgoCD, ESO, Ingress, cert-manager — not yet present.

# Communication Map
No Dapr communication — this repo deploys Dapr itself.
No application secrets — manages the secret infrastructure itself.

# Development Standards
- All Helm releases must use explicit chart versions (no `latest`)
- Namespace isolation: each component gets its own namespace (e.g. dapr-system)
- Changes to global infrastructure must be tested in local k3d before applying to on-prem/cloud
- Document all manual steps in justfile recipes
- `skaffold.env` is the source of truth for platform-wide constants; other repos copy it

# Commit Convention
Use Conventional Commits: feat(infra):, fix(infra):, chore(infra):
Example: feat(infra): add vault helm release

# Testing Strategy
Validate: `skaffold diagnose`
Integration: Deploy to local k3d cluster (`just deploy`), verify all components running
`kubectl get pods --all-namespaces` to verify
Priority: Manual verification 100% — infrastructure has no unit tests
