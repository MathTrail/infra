# MathTrail Infrastructure Bootstrap
#
# Usage:
#   just deploy          — full bootstrap: ArgoCD + infrastructure
#   just delete          — remove ArgoCD Applications (ordered: VCO CRs first)
#   just delete-all      — remove ArgoCD + Applications (full teardown)
#   just status          — show status of all infrastructure Applications
#   just argocd-ui       — open ArgoCD UI at localhost:8080
#
# Optional: create .env with GITHUB_TOKEN if the repository is private.

set shell := ["bash", "-c"]
set dotenv-load := true
set dotenv-filename := "platform.env"

# Base URL where the Helm chart repo is hosted (GitHub Pages)
repo_url := env_var("CHARTS_REPO")

argocd_ns := "argocd"

# ─────────────────────────────────────────────────────────────────────────────
# PUBLIC COMMANDS
# ─────────────────────────────────────────────────────────────────────────────

# Full bootstrap: ArgoCD + all infrastructure
deploy: _install-argocd _bootstrap-infra
    @echo ""
    @echo "✅ Infrastructure ready! You can now deploy microservices."

# Remove all ArgoCD Applications (cluster and ArgoCD stay)
delete:
    #!/usr/bin/env bash
    set -euo pipefail

    # Phase 1: Remove vault-config first (VCO is still running → finalizers clear naturally)
    echo "🗑️  Removing vault-config (VCO CRs)..."
    helm uninstall vault-config-apps --namespace {{argocd_ns}} 2>/dev/null || true

    # Wait for VCO CRs to be fully removed (VCO controller handles finalizers)
    printf "  ⏳ Waiting for VCO CRs to clear..."
    elapsed=0
    while [ $elapsed -lt 60 ]; do
      remaining=$(kubectl -n {{argocd_ns}} get application vault-config \
        -o name 2>/dev/null || echo "")
      if [ -z "$remaining" ]; then
        echo " done"
        break
      fi
      sleep 5
      elapsed=$((elapsed + 5))
    done
    if [ $elapsed -ge 60 ]; then
      echo " timeout (forcing)"
      # Fallback: strip VCO CR finalizers if controller couldn't handle them
      for crd in $(kubectl api-resources --api-group=redhatcop.redhat.io -o name 2>/dev/null); do
        for name in $(kubectl get "$crd" -n vault-config-operator --no-headers \
                        -o custom-columns=':metadata.name' 2>/dev/null); do
          [ -z "$name" ] && continue
          kubectl -n vault-config-operator patch "$crd" "$name" \
            --type=merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
        done
      done
      # Strip Application finalizer if still stuck
      kubectl -n {{argocd_ns}} patch application vault-config \
        --type=merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
    fi

    # Phase 2: Remove remaining app-of-apps releases
    echo "🗑️  Removing remaining Applications..."
    for release in cert-manager-apps external-secrets-apps storageclass-apps chaos-mesh-apps vault-apps; do
        helm uninstall "$release" --namespace {{argocd_ns}} 2>/dev/null || true
    done
    sleep 5

    # Phase 3: Wait for Terminating namespaces
    for ns in vault-config-operator vault vault-secrets-operator cert-manager external-secrets chaos-mesh; do
      phase=$(kubectl get ns "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
      if [ "$phase" = "Terminating" ]; then
        printf "  Waiting for namespace/%s... " "$ns"
        if kubectl wait --for=delete namespace/"$ns" --timeout=30s 2>/dev/null; then
          echo "done"
        else
          echo "still stuck (may need manual intervention)"
        fi
      fi
    done

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

    GIT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
    for chart in cert-manager vault vault-config external-secrets storageclass chaos-mesh; do
        helm upgrade --install "${chart}-apps" "{{justfile_directory()}}/charts/${chart}" \
          --namespace {{argocd_ns}} \
          --set gitBranch="$GIT_BRANCH" \
          --timeout 60s
    done
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
