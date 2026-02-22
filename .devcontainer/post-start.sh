#!/bin/bash
set -e

# Load platform environment
set -a; source /etc/mathtrail/platform.env; set +a

# Set up skaffold.env
ln -sf /etc/mathtrail/platform.env "$PWD/skaffold.env"

# Set up kubeconfig from host bind mount (mount is root-owned, hence sudo)
mkdir -p /home/vscode/.kube
KUBECONFIG_SRC="/home/vscode/.kube-host/${CLUSTER_NAME}.yaml"

if sudo test -f "$KUBECONFIG_SRC"; then
    sudo install -o vscode -g vscode -m 600 "$KUBECONFIG_SRC" /home/vscode/.kube/config
    echo "Kubeconfig ready"
else
    echo "Warning: kubeconfig not found at $KUBECONFIG_SRC"
    echo "Run 'just kubeconfig' in infra-local-k3s on host first"
fi

# Verify cluster connection
kubectl cluster-info 2>/dev/null && echo "Connected to cluster" \
    || echo "Cluster not accessible — check that k3d is running on host"
