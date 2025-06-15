# Secure AKS Deployment

This repository contains a secure deployment of an AKS cluster with Istio, ArgoCD, and other security-focused components.

## Prerequisites

- Azure CLI
- kubectl
- Terraform
- Docker
- Git

## Quick Start

1. Clone the repository:
   ```bash
   git clone https://github.com/your-org/secure-aks1.git
   cd secure-aks1
   ```

2. Deploy the infrastructure:
   ```bash
   cd infrastructure
   terraform init
   terraform apply
   ```

3. Get cluster credentials:
   ```bash
   az aks get-credentials --resource-group akssecuredemo-rg --name akssecuredemo-aks
   ```

4. Deploy ArgoCD:
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
   ```

## Security Features

- AKS with Azure AD integration
- Istio service mesh with mTLS
- Network policies
- TLS encryption
- Rate limiting
- JWT validation
- Vault for secrets management

## Components

- **Infrastructure**: Terraform configurations for AKS and supporting resources
- **ArgoCD Apps**: GitOps configurations for application deployment
- **Istio Config**: Service mesh configurations
- **Helm Charts**: Application deployments
- **Scripts**: Utility scripts for management

## Maintenance

- Use `scripts/teardown.sh` to clean up resources
- Monitor logs with `kubectl logs -n <namespace> <pod-name>`
- Check ArgoCD status: `kubectl get applications -n argocd`

## Security Notes

- All traffic is encrypted with TLS
- mTLS is enabled for service-to-service communication
- Network policies restrict pod-to-pod communication
- Secrets are managed through Azure Key Vault
- Regular security updates are applied through ArgoCD

## Troubleshooting

1. Check pod status:
   ```bash
   kubectl get pods -A
   ```

2. View ArgoCD sync status:
   ```bash
   kubectl get applications -n argocd
   ```

3. Check Istio gateway:
   ```bash
   kubectl get gateway -n istio-system
   ```

## License

MIT License - see LICENSE file for details
