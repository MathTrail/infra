# MathTrail Infrastructure

set shell := ["bash", "-c"]

# Deploy all infrastructure components to the cluster
deploy:
    skaffold deploy

# Delete all deployed infrastructure components from the cluster
delete:
    skaffold delete
