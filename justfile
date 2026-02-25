# MathTrail Infrastructure

set shell := ["bash", "-c"]

# Deploy all infrastructure components to the cluster
deploy:
    skaffold deploy

# Delete all deployed infrastructure components from the cluster
delete:
    skaffold delete
    # Helm does not remove CRDs on uninstall by design, so clean them up manually
    -kubectl delete crds -l app.kubernetes.io/part-of=dapr
    # Bank-Vaults: delete Vault CR first (triggers operator cleanup), then CRDs
    -kubectl delete vault --all -n vault
    -kubectl delete crds vaults.vault.banzaicloud.com
    -kubectl delete namespace dapr-system
    -kubectl delete namespace vault
    -kubectl delete namespace external-secrets
    -kubectl delete namespace ambassador
