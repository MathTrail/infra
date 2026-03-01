# Identity & Context
You are an infrastructure expert working on mathtrail-infra — the umbrella repo for global cluster resources.
This repo deploys cluster-level components that all services depend on.
This is NOT a service — it manages shared infrastructure.

Tech Stack: Helm, ArgoCD, Just, Vault Config Operator (VCO), Vault Secrets Operator (VSO)
Infra: All Helm charts are vendored in mathtrail-charts repo (https://MathTrail.github.io/charts/charts)

# Repo Layout
- `platform.env` — platform constants shared across all MathTrail repos (namespace, registry, chart repo URL, cluster name)
- `justfile` — developer-facing recipes (`just deploy`, `just delete`)
- `apps/` — one self-contained folder per ArgoCD Application (each is a minimal Helm chart):
  - `cert-manager/` — cert-manager controller (wave 0, multi-source with helm-values.yaml)
  - `cert-manager-config/` — ClusterIssuers from manifests/ (wave 2)
  - `vault/` — Vault server HA Raft (wave 1, multi-source with helm-values.yaml)
  - `vault-init/` — RBAC + init Job from manifests/ (wave 2)
  - `vault-config-operator/` — VCO operator (wave 3, multi-source with helm-values.yaml + manifest)
  - `vault-config/` — VCO CRs: policies + K8s auth roles (wave 4, resources/ subdir)
  - `vault-secrets-operator/` — VSO operator (wave 4, multi-source with helm-values.yaml)
  - `external-secrets/` — ESO operator (wave 1, single-source chart)
  - `storageclass/` — on-prem StorageClass from gitops repo
  - `chaos-mesh/` — Chaos Mesh (deploy: false by default)
  - `chaos-experiments/` — chaos experiments from gitops repo (deploy: false by default)
  Each folder contains: Chart.yaml, values.yaml, templates/application.yaml, optional helm-values.yaml, optional resources/
- `manifests/` — raw K8s YAML:
  - `vault-namespace.yaml` — creates the `vault` namespace
  - `namespace.yaml` — creates the `mathtrail` application namespace
  - `vault-unseal-key-secret.yaml` — empty unseal-key Secret placeholder for Vault startup
  - `vault-rbac.yaml` — ServiceAccount, Roles, ClusterRoleBinding for Vault
  - `vault-init-rbac.yaml` — RBAC for the vault-init Job
  - `vault-init-job.yaml` — idempotent Job that initializes + unseals Vault
  - `cluster-secret-store.yaml` — ESO ClusterSecretStore for Database Secrets Engine
  - `cluster-secret-store-kv.yaml` — ESO ClusterSecretStore for KV v2

# What Is Currently Deployed
- **vault-prereqs**: `vault` namespace + `mathtrail` namespace + unseal-key Secret placeholder
- **HashiCorp Vault** (Helm release into `vault` namespace, HA Raft — 3 replicas prod, 1 dev)
- **vault-init**: RBAC + idempotent init Job (initializes cluster, unseals with Shamir keys)
- **Vault Config Operator (VCO)** (Helm release into `vault-config-operator` namespace)
  - Reconciles VaultConnection, VaultAuth, Policy, SecretEngineMount, DatabaseSecretEngineRole, etc.
- **VCO Custom Resources** (`apps/vault-config/resources/`):
  - Kubernetes auth method (ESO role + app-reader role + db-admin role)
  - Database Secrets Engine mount + per-service configs/roles
  - KV v2 Secrets Engine + seed secrets
- **Vault Secrets Operator (VSO)** (Helm release into `vault-secrets-operator` namespace)
  - Writes Vault dynamic secrets into K8s Secrets
  - Triggers rolling restarts on lease renewal
- **External Secrets Operator** (Helm release into `external-secrets` namespace)
- **Two ClusterSecretStores** (`vault-backend` for database, `vault-kv-backend` for KV v2)
- **Telepresence** traffic-manager (Helm release into `ambassador` namespace)

# Deploy Chain

## justfile (Helm — ArgoCD Application CRs)
```
just deploy
  Step 1: _install-argocd  — install ArgoCD + AppProject
  Step 2: _bootstrap-infra — install all apps/* as Helm releases (each wraps one ArgoCD Application):
          then wait for ArgoCD to sync all Applications by wave:
            Wave 0: cert-manager
            Wave 1: vault, external-secrets
            Wave 2: cert-manager-config, vault-init
            Wave 3: vault-config-operator
            Wave 4: vault-config, vault-secrets-operator
```

# Vault Architecture
- **HashiCorp Vault** in HA Raft mode (3 replicas prod, 1 replica dev)
- **Shamir unseal**: vault-init Job initializes Vault, unseals with Shamir keys, stores keys in `vault-unseal-key` Secret
- **VCO** (Vault Config Operator) manages all Vault configuration declaratively via CRs
- **VSO** (Vault Secrets Operator) syncs Vault secrets into K8s Secrets for pods
  - Pods consume credentials via `secretKeyRef` env vars
  - VSO triggers rolling restarts on lease renewal — no in-process refresh needed
- **Per-service DB configs** are declared as VCO CRs in `apps/vault-config/resources/{service}/`
- Adding a new service: add a new resource file in `apps/vault-config/resources/` — no Helm changes

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
- `platform.env` is the source of truth for platform-wide constants; other repos copy it
- Vault configuration is declarative via VCO CRs — never use imperative `vault write` commands

# Commit Convention
Use Conventional Commits: feat(infra):, fix(infra):, chore(infra):
Example: feat(infra): add profile-api vault db role via VCO

# Testing Strategy
Integration: Deploy to local k3d cluster (`just deploy`), verify all components running
`kubectl get pods --all-namespaces` to verify
`kubectl get pods -n vault` to verify Vault pods
`kubectl get vaultconnection,vaultauth -n vault-config` to verify VCO CRs
Priority: Manual verification 100% — infrastructure has no unit tests
