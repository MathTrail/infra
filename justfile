# MathTrail Infrastructure Bootstrap
#
# Usage:
#   just deploy          — full bootstrap: ArgoCD + infrastructure
#   just delete          — remove ArgoCD Applications (cluster stays)
#   just status          — show status of all infrastructure Applications
#   just argocd-ui       — open ArgoCD UI at localhost:8080
#
# Optional: create .env with GITHUB_TOKEN if the repository is private.

set shell := ["bash", "-c"]
set dotenv-load := true
set dotenv-filename := "skaffold.env"

# Path to sibling gitops repository
# Override via .env for non-standard layout (GITOPS_DIR)
gitops_dir := env_var_or_default("GITOPS_DIR", justfile_directory() + "/../gitops")

# Base URL where the Helm chart repo is hosted (GitHub Pages)
repo_url := env_var("CHARTS_REPO_ROOT")

argocd_ns := "argocd"

# ─────────────────────────────────────────────────────────────────────────────
# PUBLIC COMMANDS
# ─────────────────────────────────────────────────────────────────────────────

# Full bootstrap: ArgoCD + all infrastructure
deploy: _install-argocd _bootstrap-infra
    @echo ""
    @echo "✅ Infrastructure ready! You can now run skaffold dev in microservices."

# Remove all ArgoCD Applications (cluster and ArgoCD stay)
delete:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🗑️  Removing ArgoCD Applications..."
    kubectl delete -f "{{gitops_dir}}/apps/infrastructure/" --ignore-not-found
    echo "✅ Applications removed. Cluster and ArgoCD keep running."

# Show infrastructure Applications status (ordered by sync-wave)
status:
    #!/usr/bin/env bash
    kubectl -n {{argocd_ns}} get applications \
      -o custom-columns='NAME:.metadata.name,WAVE:.metadata.annotations.argocd\.argoproj\.io/sync-wave,SYNC:.status.sync.status,HEALTH:.status.health.status' \
      --sort-by='.metadata.annotations.argocd\.argoproj\.io/sync-wave' 2>/dev/null \
      || echo "ArgoCD is not installed or cluster is unreachable."

# Open ArgoCD UI at localhost:8080 (Ctrl+C to exit)
argocd-ui:
    #!/usr/bin/env bash
    PASS=$(kubectl -n {{argocd_ns}} get secret argocd-initial-admin-secret \
      -o jsonpath="{.data.password}" | base64 -d)
    echo "ArgoCD UI: http://localhost:8080"
    echo "Login:     admin / $PASS"
    kubectl -n {{argocd_ns}} port-forward svc/argocd-server 8080:80

# ─────────────────────────────────────────────────────────────────────────────
# INTERNAL RECIPES
# ─────────────────────────────────────────────────────────────────────────────

# Step 1: install ArgoCD + create AppProject + configure repo access
[private]
_install-argocd:
    #!/usr/bin/env bash
    set -euo pipefail
    echo ""
    echo "🐙 Step 1/2 — ArgoCD..."

    helm upgrade --install argocd argo-cd \
      --repo {{repo_url}} \
      --namespace {{argocd_ns}} --create-namespace \
      --set server.insecure=true \
      --wait --timeout 120s

    echo "  ✅ ArgoCD installed."

    # AppProject mathtrail — must exist before applying Applications
    kubectl apply -f "{{justfile_directory()}}/manifests/argocd-project.yaml"
    echo "  ✅ AppProject 'mathtrail' created."

    # If the repo is private — configure access via kubectl (no argocd CLI needed)
    if [ -n "${GITHUB_TOKEN:-}" ]; then
    echo "  🔑 Configuring private repository access..."
    envsubst < "{{justfile_directory()}}/manifests/argocd-repo-creds.yaml" | kubectl apply -f -
    echo "  ✅ Repository access configured."
    fi

# Step 2: apply Applications and wait for all waves to complete
[private]
_bootstrap-infra:
    #!/usr/bin/env bash
    set -euo pipefail
    echo ""
    echo "🌊 Step 2/2 — Infrastructure via ArgoCD (sync-waves 0 → 4)..."

    kubectl apply -f "{{gitops_dir}}/apps/infrastructure/"
    echo "  Applications applied. ArgoCD sync in progress..."

    # Wait for Applications sequentially by wave for clear progress output
    _wait_app() {
      local app=$1 timeout=${2:-600} elapsed=0
      printf "    ⏳ %-38s" "$app"
      while [ $elapsed -lt $timeout ]; do
        local health
        health=$(kubectl -n {{argocd_ns}} get application "$app" \
          -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")
        if [ "$health" = "Healthy" ]; then
          echo "✅ Healthy"
          return 0
        fi
        sleep 10
        elapsed=$((elapsed + 10))
      done
      echo "❌ timeout (${timeout}s)"
      return 1
    }

    echo ""
    echo "  Wave 0:"
    _wait_app cert-manager 300

    echo "  Wave 1:"
    _wait_app vault           360
    _wait_app external-secrets 240

    echo "  Wave 2:"
    _wait_app cert-manager-config 240
    _wait_app vault-init           360

    echo "  Wave 3:"
    _wait_app vault-config-operator 360

    echo "  Wave 4:"
    _wait_app vault-config           360
    _wait_app vault-secrets-operator 360

    echo ""
    echo "  All waves completed."

# ─────────────────────────────────────────────────────────────────────────────
# DIRECT HELM INSTALLS (bypass ArgoCD — use for debugging or first-time setup)
# ─────────────────────────────────────────────────────────────────────────────

# Bootstrap the entire infrastructure in dependency order via direct Helm.
install-infra:
    #!/usr/bin/env bash
    set -euo pipefail
    INFRA="{{justfile_directory()}}"
    REPO="{{repo_url}}"

    # Phase A — cert-manager, ESO, Telepresence in parallel.
    # Capture PIDs and wait on each individually so set -e catches failures.
    helm upgrade --install cert-manager "$REPO/cert-manager" \
      --namespace cert-manager --create-namespace \
      --values "$INFRA/values/cert-manager-values.yaml" --wait &
    CERT_PID=$!
    helm upgrade --install external-secrets "$REPO/external-secrets" \
      --namespace external-secrets --create-namespace \
      --values "$INFRA/values/external-secrets-values.yaml" --wait &
    ESO_PID=$!
    helm upgrade --install traffic-manager "$REPO/telepresence-oss" \
      --namespace ambassador --create-namespace \
      --values "$INFRA/values/telepresence-values.yaml" --wait &
    TEL_PID=$!
    wait $CERT_PID; wait $ESO_PID; wait $TEL_PID

    # Phase B — wait for cert-manager webhook to be fully registered before
    # applying Certificate/Issuer CRDs (API server needs webhook to validate them).
    kubectl wait --for=condition=Available deployment/cert-manager-webhook \
      --namespace cert-manager --timeout=60s

    kubectl apply -f "$INFRA/manifests/cert-manager-issuers.yaml"
    kubectl wait --for=condition=Ready certificate \
      --namespace vault-config-operator vco-webhook-cert --timeout=120s

    # Phase C — Vault prerequisites (namespaces + unseal-key placeholder Secret).
    kubectl apply -f "$INFRA/manifests/vault-namespace.yaml"
    kubectl apply -f "$INFRA/manifests/namespace.yaml"
    kubectl apply -f "$INFRA/manifests/vault-unseal-key-secret.yaml"

    # Phase D — Vault Helm chart (starts sealed/uninitialized).
    helm upgrade --install vault "$REPO/vault" \
      --namespace vault --create-namespace \
      --values "$INFRA/values/vault-values.yaml" --wait

    # Phase E — Vault init RBAC + idempotent init Job.
    # vault-init-rbac.yaml grants get/create/update/patch on Secrets so the Job
    # can write the Kubernetes Seal root key to vault-unseal-key Secret.
    kubectl apply -f "$INFRA/manifests/vault-rbac.yaml"
    kubectl apply -f "$INFRA/manifests/vault-init-rbac.yaml"
    kubectl apply -f "$INFRA/manifests/vault-init-job.yaml"
    kubectl wait --for=condition=Complete job/vault-init \
      --namespace vault --timeout=300s

    # Phase F — VCO (webhook-server-cert Secret already created by cert-manager in Phase B).
    helm upgrade --install vault-config-operator "$REPO/vault-config-operator" \
      --namespace vault-config-operator --create-namespace \
      --values "$INFRA/values/vault-config-operator-values.yaml" --wait

    # Patch VCO webhook configurations with cert-manager cainjector annotation.
    # The RedHat CoP VCO chart does not expose certManager.enabled in values,
    # so we annotate the webhook objects after Helm creates them.
    for wh in $(kubectl get mutatingwebhookconfigurations,validatingwebhookconfigurations \
                -o name | grep vault-config-operator); do
      kubectl annotate "$wh" \
        cert-manager.io/inject-ca-from=vault-config-operator/vco-webhook-cert \
        --overwrite
    done

    # Phase G — VSO
    helm upgrade --install vault-secrets-operator "$REPO/vault-secrets-operator" \
      --namespace vault-secrets-operator --create-namespace \
      --values "$INFRA/values/vault-secrets-operator-values.yaml" --wait

    # Phase H — VCO CRs (kustomize)
    kubectl apply -k "$INFRA/vault-config/"

    # Phase I — ESO ClusterSecretStores
    kubectl apply -f "$INFRA/manifests/cluster-secret-store.yaml"
    kubectl apply -f "$INFRA/manifests/cluster-secret-store-kv.yaml"

# Individual recipes for partial upgrades / re-installs.
install-cert-manager:
    helm upgrade --install cert-manager {{repo_url}}/cert-manager \
      --namespace cert-manager --create-namespace \
      --values {{justfile_directory()}}/values/cert-manager-values.yaml --wait

install-vault:
    helm upgrade --install vault {{repo_url}}/vault \
      --namespace vault \
      --values {{justfile_directory()}}/values/vault-values.yaml --wait

install-vco:
    helm upgrade --install vault-config-operator {{repo_url}}/vault-config-operator \
      --namespace vault-config-operator \
      --values {{justfile_directory()}}/values/vault-config-operator-values.yaml --wait

install-vso:
    helm upgrade --install vault-secrets-operator {{repo_url}}/vault-secrets-operator \
      --namespace vault-secrets-operator \
      --values {{justfile_directory()}}/values/vault-secrets-operator-values.yaml --wait

install-eso:
    helm upgrade --install external-secrets {{repo_url}}/external-secrets \
      --namespace external-secrets \
      --values {{justfile_directory()}}/values/external-secrets-values.yaml --wait
