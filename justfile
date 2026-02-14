deploy:
    helm repo add mathtrail https://MathTrail.github.io/charts/charts
    helm upgrade --install dapr mathtrail/dapr \
        --namespace dapr-system \
        --create-namespace \
        --wait
