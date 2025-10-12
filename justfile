start:
    minikube start --profile mathtrail-dev \
        --driver docker \
        --memory 4096 \
        --cpus 2 \
        --ports=30000:30000 \
        --addons=ingress \
        --mount-string="/var/run/docker.sock:/var/run/docker.sock" \
        --mount

deploy:
    helm upgrade --install dapr ./helm/external/dapr/dapr-1.16.1.tgz \
        --namespace dapr-system \
        --create-namespace \
        --wait
