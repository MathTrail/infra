# MathTrail Infrastructure Bootstrap
#
# Usage:
#   just deploy      — full bootstrap: ArgoCD + infrastructure
#   just delete      — remove ArgoCD Applications (ordered: VCO CRs first)
#   just nuke        — remove ArgoCD + Applications (full teardown)
#   just status      — show status of all infrastructure Applications
#   just argocd-ui   — open ArgoCD UI at localhost:8080

set shell := ["bash", "-c"]
set dotenv-load := true
set dotenv-filename := "platform.env"

argocd_ns := "argocd"

# ─────────────────────────────────────────────────────────────────────────────
# PUBLIC COMMANDS
# ─────────────────────────────────────────────────────────────────────────────

# Full bootstrap: ArgoCD + all infrastructure
deploy:
    ansible-galaxy collection install -r ansible/requirements.yml --force
    ansible-playbook -i ansible/inventory/local.yml playbooks/deploy.yml

# Remove all ArgoCD Applications (cluster and ArgoCD stay)
delete:
    ansible-playbook -i ansible/inventory/local.yml playbooks/delete.yml

# Remove ArgoCD + all Applications (full teardown, cluster stays)
nuke:
    ansible-playbook -i ansible/inventory/local.yml playbooks/nuke.yml

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
