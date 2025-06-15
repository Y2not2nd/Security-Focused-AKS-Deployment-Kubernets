#!/bin/bash
# Teardown script to remove all deployed resources
set -e

echo "Deleting ArgoCD applications..."
kubectl delete application frontend-app backend-app mongodb-app vault-app istio-base-app istio-cp-app istio-gateway-app istio-config-app monitoring-app -n argocd --ignore-not-found

echo "Destroying Azure infrastructure with Terraform..."
cd infrastructure/
terraform destroy -auto-approve 