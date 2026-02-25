# Identity & Context
You are an infrastructure expert working on mathtrail-infra — the umbrella repo for global cluster resources.
This repo deploys cluster-level components that all services depend on.
This is NOT a service — it manages shared infrastructure.

Tech Stack: Helm, Skaffold, Just, Bank-Vaults Operator
Infra: Deploys remote charts from mathtrail-charts Helm repo (https://MathTrail.github.io/charts/charts)

# Repo Layout
- `skaffold.yaml` — orchestrates deploy: Helm releases + raw manifests
- `skaffold.env` — platform constants shared across all MathTrail repos (namespace, registry, chart repo URL, cluster name)
- `justfile` — developer-facing recipes (`just deploy`, `just delete`)
- `dapr/` — raw Kubernetes manifests applied alongside Helm:
  - `namespace.yaml` — creates the `mathtrail` application namespace
  - `components.yaml` — Dapr component definitions (statestore, etc.)
- `values/` — Helm values for: vault-operator, external-secrets, telepresence
- `manifests/` — raw K8s YAML:
  - `vault-rbac.yaml` — ServiceAccount, Roles, ClusterRoleBinding for Vault
  - `vault-instance.yaml` — Bank-Vaults Vault CR (global config only: engine mounts, auth, policies, KV, startupSecrets)
  - `cluster-secret-store.yaml` — ESO ClusterSecretStore for Database Secrets Engine
  - `cluster-secret-store-kv.yaml` — ESO ClusterSecretStore for KV v2 Secrets Engine

# What Is Currently Deployed
- **Dapr** (Helm release into `dapr-system` namespace, from remote chart)
- **mathtrail namespace** (raw manifest)
- **Dapr in-memory statestore** component (raw manifest, applied to default namespace from skaffold.env)
- **Dapr Vault Secret Store components** (`vault` for KV v2, `vault-db` for Database engine)
  - Both use Kubernetes auth with `dapr-reader-role` in `mathtrail` namespace
  - The approved way for Go microservices to access Vault secrets
- **Bank-Vaults Operator** (Helm release into `vault` namespace, OCI chart from ghcr.io)
- **Vault instance** (Bank-Vaults CR — persistent file storage, auto-unseal via K8s Secret)
  - Kubernetes auth method (ESO role + Dapr role + db-admin role for service Jobs)
  - Database Secrets Engine mount (empty — per-service Jobs create configs/roles)
  - KV v2 Secrets Engine (static secrets: passwords, DSNs, API keys)
  - ESO policy + role (`eso-role` bound to `external-secrets` SA)
  - Dapr read policy + role (`dapr-reader-role` — any SA in `mathtrail` namespace)
  - DB admin policy + role (`db-admin-role` — any SA in `mathtrail` namespace)
- **External Secrets Operator** (Helm release into `external-secrets` namespace)
- **Two ClusterSecretStores** (`vault-backend` for database, `vault-kv-backend` for KV v2)
- **Telepresence** traffic-manager (Helm release into `ambassador` namespace)

# Skaffold Deploy Chain
```
mathtrail-infra (top-level)
  requires:
    Phase 1 (parallel): dapr, vault-operator, external-secrets, telepresence
    Phase 2 (sequential): vault-instance (RBAC + Vault CR)
    Phase 3 (sequential): vault-secret-stores (ClusterSecretStores)
```

# Vault Architecture (Bank-Vaults)
- **Operator** reconciles the Vault CR every 30s
- **vault-configurer** sidecar applies externalConfig idempotently
- **Auto-unseal**: operator stores unseal keys in K8s Secret `vault-unseal-keys`
- **externalConfig** contains global config only: auth, policies, engine mounts, KV startupSecrets
- **Per-service DB configs** are NOT in the CR — each service repo has a `vaultDbConfigJob`
  Helm hook that runs `vault write database/config/...` + `vault write database/roles/...`
  using the `db-admin-role` Kubernetes auth role
- The CR declares `configuration.config: []` and `configuration.roles: []` stubs so the
  configurer doesn't purge Job-created entries (merge, not replace behavior)
- Adding a new service: enable `vaultDbConfig` in the service's Helm values — no infra repo changes

# Decentralized DB Config Pattern
Each service that needs dynamic DB credentials owns its config via `mathtrail-service-lib.vaultDbConfigJob`:
1. Helm hook Job (pre-install/pre-upgrade, weight -5) runs before migration Job (weight 5)
2. Init container waits for Vault readiness (`/v1/sys/health`)
3. Main container authenticates via Kubernetes auth (`db-admin-role`)
4. Writes `database/config/<name>` (PG connection) and `database/roles/<name>` (dynamic role)
5. SQL statements are written to temp files to avoid escaping issues (`@/tmp/create.sql`)
6. PG admin password comes from `postgres-postgresql` Secret (Bitnami chart), NOT from a separate Secret

# Secret Management Architecture (Platform Standard)

## Rule: How secrets reach consumers

| Consumer | Mechanism | Rationale |
|---|---|---|
| Go microservices | Dapr Secret Store (`vault` / `vault-db` components) | Secrets stay in memory, never touch etcd |
| Grafana, Kratos, Hydra, Ingress | ESO → K8s Secret | These tools require native K8s Secrets |

**Microservice rule**: Never use `envFrom.secretRef`, env var passwords, or ESO ExternalSecrets
for Go service pods. Use `daprClient.GetSecret()` exclusively.

## Dapr Vault Components (mathtrail namespace)
Defined in `dapr/vault-secret-store.yaml`:

- **`vault`** — KV v2 engine (`secret/`) — static secrets: Redis passwords, API keys
  ```go
  secret, _ := daprClient.GetSecret(ctx, "vault", "local/mathtrail-mentor", nil)
  redisPassword := secret["redis-password"]
  ```
- **`vault-db`** — Database engine (`database/`) — dynamic PostgreSQL credentials
  ```go
  creds, _ := daprClient.GetSecret(ctx, "vault-db", "creds/mentor-api-role", nil)
  // creds = {"username": "v-mentor-xyz", "password": "A1a-..."}
  // Each call creates a NEW Vault lease (new username/password pair)
  ```

## Vault Auth Roles

| Role | Bound to | Policy | Purpose |
|---|---|---|---|
| `dapr-reader-role` | any SA in `mathtrail` | `dapr-read-policy` | Dapr sidecar reads secrets |
| `eso-role` | `external-secrets` SA | `eso-policy` | ESO syncs secrets for infra tools |
| `db-admin-role` | any SA in `mathtrail` | `db-admin-policy` | vault-db-config Jobs configure DB engine |

## Communication Map
No Dapr communication — this repo deploys Dapr itself.
No application secrets — manages the secret infrastructure itself.

# Development Standards
- All Helm releases must use explicit chart versions (no `latest`)
- Namespace isolation: each component gets its own namespace (e.g. dapr-system, vault, external-secrets)
- Changes to global infrastructure must be tested in local k3d before applying to on-prem/cloud
- Document all manual steps in justfile recipes
- `skaffold.env` is the source of truth for platform-wide constants; other repos copy it
- Vault configuration is declarative: never use imperative `vault write` commands in the infra repo
  (per-service `vault write` Jobs are the intended pattern for DB configs in service repos)

# Commit Convention
Use Conventional Commits: feat(infra):, fix(infra):, chore(infra):
Example: feat(infra): migrate vault to bank-vaults operator

# Testing Strategy
Validate: `skaffold diagnose`
Integration: Deploy to local k3d cluster (`just deploy`), verify all components running
`kubectl get pods --all-namespaces` to verify
`kubectl get vault -n vault` to verify Vault CR status
Priority: Manual verification 100% — infrastructure has no unit tests
