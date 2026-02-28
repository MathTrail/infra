# Identity & Context
You are an infrastructure expert working on mathtrail-infra — the umbrella repo for global cluster resources.
This repo deploys cluster-level components that all services depend on.
This is NOT a service — it manages shared infrastructure.

Tech Stack: Helm, Skaffold, Just, Vault Config Operator (VCO), Vault Secrets Operator (VSO)
Infra: All Helm charts are vendored in mathtrail-charts repo (https://MathTrail.github.io/charts/charts)

# Repo Layout
- `skaffold.yaml` — orchestrates deploy: Helm releases + raw manifests (multi-config, phased)
- `skaffold.env` — platform constants shared across all MathTrail repos (namespace, registry, chart repo URL, cluster name)
- `justfile` — developer-facing recipes (`just deploy`, `just delete`)
- `values/` — Helm values for: vault, external-secrets, telepresence
- `manifests/` — raw K8s YAML:
  - `vault-namespace.yaml` — creates the `vault` namespace
  - `namespace.yaml` — creates the `mathtrail` application namespace
  - `vault-unseal-key-secret.yaml` — empty unseal-key Secret placeholder for Vault startup
  - `vault-rbac.yaml` — ServiceAccount, Roles, ClusterRoleBinding for Vault
  - `vault-init-rbac.yaml` — RBAC for the vault-init Job
  - `vault-init-job.yaml` — idempotent Job that initializes + unseals Vault
  - `cluster-secret-store.yaml` — ESO ClusterSecretStore for Database Secrets Engine
  - `cluster-secret-store-kv.yaml` — ESO ClusterSecretStore for KV v2
- `vault-config/` — Kustomize overlay with VCO Custom Resources:
  - `_base/` — VaultConnection, VaultAuth, policies, engine mounts, K8s auth roles, KV seeds
  - `mentor-api/` — per-service DB engine config + role for Mentor
  - `profile-api/` — per-service DB engine config + role for Profile

# What Is Currently Deployed
- **vault-prereqs**: `vault` namespace + `mathtrail` namespace + unseal-key Secret placeholder
- **HashiCorp Vault** (Helm release into `vault` namespace, HA Raft — 3 replicas prod, 1 dev)
- **vault-init**: RBAC + idempotent init Job (initializes cluster, writes seal key, auto-unseals)
- **Vault Config Operator (VCO)** (Helm release into `vault-config-operator` namespace)
  - Reconciles VaultConnection, VaultAuth, Policy, SecretEngineMount, DatabaseSecretEngineRole, etc.
- **VCO Custom Resources** (Kustomize — `vault-config/`):
  - Kubernetes auth method (ESO role + app-reader role + db-admin role)
  - Database Secrets Engine mount + per-service configs/roles
  - KV v2 Secrets Engine + seed secrets
- **Vault Secrets Operator (VSO)** (Helm release into `vault-secrets-operator` namespace)
  - Writes Vault dynamic secrets into K8s Secrets
  - Triggers rolling restarts on lease renewal
- **External Secrets Operator** (Helm release into `external-secrets` namespace)
- **Two ClusterSecretStores** (`vault-backend` for database, `vault-kv-backend` for KV v2)
- **Telepresence** traffic-manager (Helm release into `ambassador` namespace)

# Skaffold Deploy Chain
```
mathtrail-infra (top-level)
  requires:
    Phase 1 (parallel): vault-prereqs, external-secrets, telepresence
    Phase 2: vault (HashiCorp Vault Helm chart, needs namespace + unseal-key)
    Phase 3: vault-init (init Job — initializes + unseals)
    Phase 4: vault-config-operator (VCO — needs Vault initialized)
    Phase 5 (parallel): vault-config (VCO CRs), vault-secrets-operator (VSO)
    Phase 6: vault-secret-stores (ESO ClusterSecretStores — needs KV engine configured)
```

# Vault Architecture
- **HashiCorp Vault** in HA Raft mode (3 replicas prod, 1 replica dev via Skaffold profile)
- **Auto-unseal**: vault-init Job writes unseal keys to K8s Secret `vault-unseal-key`
- **VCO** (Vault Config Operator) manages all Vault configuration declaratively via CRs
- **VSO** (Vault Secrets Operator) syncs Vault secrets into K8s Secrets for pods
  - Pods consume credentials via `secretKeyRef` env vars
  - VSO triggers rolling restarts on lease renewal — no in-process refresh needed
- **Per-service DB configs** are declared as VCO CRs in `vault-config/{service}/`
- Adding a new service: add a new Kustomize overlay in `vault-config/` — no Helm changes

# Secret Management Architecture (Platform Standard)

## Rule: How secrets reach consumers

| Consumer | Mechanism | Rationale |
|---|---|---|
| Go microservices | VSO → K8s Secret (from Vault dynamic/static secrets) | Automatic lease renewal + pod restart |
| Grafana, Kratos, Hydra, Ingress | ESO → K8s Secret | These tools require native K8s Secrets |

**Microservice rule**: Vault secrets are delivered to pods via VSO as K8s Secrets with
`secretKeyRef` env vars. VSO handles lease renewal and triggers rolling restarts automatically.

## Vault Auth Roles

| Role | Bound to | Policy | Purpose |
|---|---|---|---|
| `app-reader-role` | any SA in `mathtrail` | `app-read-policy` | App pods read secrets from Vault |
| `eso-role` | `external-secrets` SA | `eso-policy` | ESO syncs secrets for infra tools |
| `db-admin-role` | any SA in `mathtrail` | `db-admin-policy` | VCO configures DB engine roles |

## Communication Map
No application communication — this repo manages shared infrastructure only.
No application secrets — manages the secret infrastructure itself.

# Development Standards
- All Helm charts are vendored in `mathtrail-charts` — never reference upstream repos directly
- Namespace isolation: each component gets its own namespace (e.g. vault, external-secrets, vault-config-operator)
- Changes to global infrastructure must be tested in local k3d before applying to on-prem/cloud
- Document all manual steps in justfile recipes
- `skaffold.env` is the source of truth for platform-wide constants; other repos copy it
- Vault configuration is declarative via VCO CRs — never use imperative `vault write` commands

# Commit Convention
Use Conventional Commits: feat(infra):, fix(infra):, chore(infra):
Example: feat(infra): add profile-api vault db role via VCO

# Testing Strategy
Validate: `skaffold diagnose`
Integration: Deploy to local k3d cluster (`just deploy`), verify all components running
`kubectl get pods --all-namespaces` to verify
`kubectl get pods -n vault` to verify Vault pods
`kubectl get vaultconnection,vaultauth -n vault-config` to verify VCO CRs
Priority: Manual verification 100% — infrastructure has no unit tests
