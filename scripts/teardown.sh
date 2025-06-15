#!/bin/bash
# Teardown script to remove all deployed resources
set -euo pipefail

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "Error: $1 is required but not installed."
        exit 1
    fi
}

# Function to check if we're connected to the right cluster
check_cluster() {
    local expected_cluster="akssecuredemo-aks"
    local current_cluster
    current_cluster=$(kubectl config current-context 2>/dev/null || echo "")
    
    if [[ -z "$current_cluster" ]]; then
        echo "Error: Not connected to any Kubernetes cluster"
        exit 1
    fi
    
    if [[ "$current_cluster" != *"$expected_cluster"* ]]; then
        echo "Warning: You are not connected to the expected cluster ($expected_cluster)"
        echo "Current cluster: $current_cluster"
        read -p "Do you want to continue? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Check prerequisites
echo "Checking prerequisites..."
check_command kubectl
check_command terraform
check_cluster

# Confirm before proceeding
echo "WARNING: This will delete all resources in the cluster and Azure infrastructure."
echo "This action cannot be undone."
read -p "Are you sure you want to proceed? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 1
fi

# Delete ArgoCD applications with retry logic
echo "Deleting ArgoCD applications..."
for app in frontend-app backend-app mongodb-app vault-app istio-base-app istio-cp-app istio-gateway-app istio-config-app monitoring-app; do
    echo "Deleting $app..."
    if ! kubectl delete application "$app" -n argocd --ignore-not-found --timeout=30s; then
        echo "Warning: Failed to delete $app, will retry once..."
        sleep 5
        kubectl delete application "$app" -n argocd --ignore-not-found --timeout=30s || true
    fi
done

# Wait for applications to be fully deleted
echo "Waiting for applications to be fully deleted..."
sleep 10

# Destroy Azure infrastructure
echo "Destroying Azure infrastructure with Terraform..."
cd infrastructure/ || exit 1
if ! terraform destroy -auto-approve; then
    echo "Error: Terraform destroy failed"
    exit 1
fi

echo "Cleanup completed successfully." 