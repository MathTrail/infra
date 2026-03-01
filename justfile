# MathTrail Infrastructure Bootstrap
#
# Usage:
#   just deploy          — full bootstrap: ArgoCD + infrastructure
#   just delete          — remove ArgoCD Applications (cluster stays)
#   just delete-all      — remove ArgoCD + Applications (full teardown)
#   just status          — show status of all infrastructure Applications
#   just argocd-ui       — open ArgoCD UI at localhost:8080
#
# Optional: create .env with GITHUB_TOKEN if the repository is private.

set shell := ["bash", "-c"]
set dotenv-load := true
set dotenv-filename := "skaffold.env"

# Base URL where the Helm chart repo is hosted (GitHub Pages)
repo_url := env_var("CHARTS_REPO")

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
    helm uninstall infra-apps --namespace {{argocd_ns}} 2>/dev/null || true
    echo "✅ Applications removed. Cluster and ArgoCD keep running."

# Remove ArgoCD + all Applications (full teardown, cluster stays)
delete-all: delete
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🗑️  Removing ArgoCD..."
    helm uninstall argocd --namespace {{argocd_ns}} 2>/dev/null || true
    kubectl delete namespace {{argocd_ns}} --ignore-not-found
    echo "✅ ArgoCD and all Applications removed. Cluster keeps running."

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

    helm upgrade --install infra-apps "{{justfile_directory()}}/chart" \
      --namespace {{argocd_ns}} \
      --set gitBranch="$(git rev-parse --abbrev-ref HEAD)" \
      --timeout 60s
    echo "  Applications applied. ArgoCD sync in progress..."

    # Wait for Applications sequentially by wave for clear progress output
    _wait_app() {
      local app=$1 timeout=${2:-600} elapsed=0
      printf "    ⏳ %-38s" "$app"

      # Give ArgoCD time to start reconciling the Application
      sleep 5

      while [ $elapsed -lt $timeout ]; do
        local health sync phase
        health=$(kubectl -n {{argocd_ns}} get application "$app" \
          -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")
        sync=$(kubectl -n {{argocd_ns}} get application "$app" \
          -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "")
        phase=$(kubectl -n {{argocd_ns}} get application "$app" \
          -o jsonpath='{.status.operationState.phase}' 2>/dev/null || echo "")

        # Fail fast on error/degraded
        if [ "$health" = "Degraded" ] || [ "$phase" = "Failed" ] || [ "$phase" = "Error" ]; then
          local msg
          msg=$(kubectl -n {{argocd_ns}} get application "$app" \
            -o jsonpath='{.status.operationState.message}' 2>/dev/null || echo "unknown error")
          echo "❌ $health (sync=$sync, phase=$phase): $msg"
          return 1
        fi

        # Success: synced + healthy
        if [ "$health" = "Healthy" ] && [ "$sync" = "Synced" ]; then
          echo "✅ Healthy (synced)"
          return 0
        fi

        sleep 10
        elapsed=$((elapsed + 10))
      done

      echo "❌ timeout (${timeout}s) — health=$health sync=$sync phase=$phase"
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
