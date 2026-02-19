#!/bin/bash
set -e

source ~/.env.shared
REGISTRY_HOST="${REGISTRY%:*}"

mkdir -p /home/vscode/.kube
chmod 700 /home/vscode/.kube

# Copy kubeconfig from host bind mount (mount is root-owned, so use sudo)
if sudo test -f "/home/vscode/.kube-host/${CLUSTER_NAME}.yaml"; then
    sudo cp "/home/vscode/.kube-host/${CLUSTER_NAME}.yaml" "/home/vscode/.kube/${CLUSTER_NAME}.yaml"
    sudo chown vscode:vscode "/home/vscode/.kube/${CLUSTER_NAME}.yaml"
    chmod 600 "/home/vscode/.kube/${CLUSTER_NAME}.yaml"
    # Rewrite API server address so it's reachable from inside the devcontainer
    sed -i 's|https://0\.0\.0\.0:|https://host.docker.internal:|g' "/home/vscode/.kube/${CLUSTER_NAME}.yaml"
    echo "Kubeconfig copied with correct permissions"
else
    echo "Warning: kubeconfig not found at /home/vscode/.kube-host/${CLUSTER_NAME}.yaml"
fi

# Make k3d registry hostname resolve to the host
HOST_IP=$(getent hosts host.docker.internal | awk '{print $1}')
if [ -n "$HOST_IP" ] && ! grep -q "$REGISTRY_HOST" /etc/hosts; then
    echo "$HOST_IP $REGISTRY_HOST" | sudo tee -a /etc/hosts > /dev/null
    echo "Added $REGISTRY_HOST -> $HOST_IP to /etc/hosts"
fi

echo "Checking cluster connection..."
if kubectl cluster-info 2>/dev/null; then
    echo "Connected to K3d cluster"
else
    echo "Cluster not accessible"
fi
