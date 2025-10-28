# Security-Focused AKS Deployment

This project sets up a secure Azure Kubernetes Service (AKS) environment that follows GitOps practices. Infrastructure is managed with Terraform, applications are packaged using Helm, Istio provides service mesh security, HashiCorp Vault handles secret management, and Argo CD keeps the cluster state in sync with Git.

---

## Architecture Overview

| Layer | Components | Notes |
| --- | --- | --- |
| Azure infrastructure | Resource group, virtual network, AKS cluster, Azure Container Registry (ACR) | Defined in `infrastructure/` using Terraform. AKS uses managed identity and integrates with Azure RBAC. |
| GitOps control plane | Argo CD with custom `argocd-cm.yaml` and `argocd-rbac-cm.yaml` | Handles automatic syncing, namespace creation, and RBAC configuration. |
| Service mesh | Istio base, control plane, ingress gateway, and policies | Deployed via Argo CD using official Istio Helm charts and local manifests. |
| Workloads | Angular frontend, Go backend API, MongoDB, Vault, Prometheus stack | Backend and frontend are local Helm charts; third-party services come from vendor charts. |
| Security controls | Istio strict mTLS, authorization policies, network policies, Vault injector, RBAC | `istio-config/` enforces mTLS and gateway rules. Backend network policy limits access to MongoDB. |
| Observability | Prometheus, Grafana, HPA metrics | Managed through Argo CD with custom configuration. |

---

## Repository Structure

```
.
├── infrastructure/          # Terraform for Azure RG, VNet, AKS, ACR, roles
├── argocd-apps/             # Argo CD application definitions
├── argocd-cm.yaml           # Argo CD ConfigMap overrides
├── argocd-rbac-cm.yaml      # Argo CD RBAC policies
├── helm-charts/
│   ├── backend/             # Go API Helm chart (with Istio and MongoDB access)
│   └── frontend/            # Angular frontend served via NGINX
├── istio-config/            # Gateway, VirtualService, mTLS, and auth policy manifests
├── src/
│   ├── backend/             # Go backend source
│   └── frontend/            # Angular frontend source
├── scripts/teardown.sh      # Removes all workloads and infrastructure
└── guide.txt                # Extended implementation notes
```

---

## Prerequisites

### Azure access

- An Azure subscription with rights to create RGs, VNets, AKS, and ACR.
- An Azure AD group object ID for AKS admin access (see `infrastructure/variables.tf`).

### Local setup

- Terraform 1.5 or newer  
- Azure CLI 2.50 or newer  
- kubectl matching the AKS version (`az aks install-cli` recommended)  
- Helm 3.12 or newer  
- Docker or another OCI-compliant image builder  
- Node.js 18 LTS and npm (for the Angular frontend)  
- Go 1.21 (for the backend API)

### Optional tools

- jq, make, and Snyk CLI (mentioned in `guide.txt` for scanning)
- kubelogin for Azure AD authentication with kubectl

---

## Deployment

### 1. Set up the environment

Authenticate and clone the repository:

```bash
az login
az account set --subscription <subscription-id>

git clone https://github.com/Y2not2nd/Security-Focused-AKS-Deployment-Kubernets.git
cd Security-Focused-AKS-Deployment-Kubernets
```

Apply the Terraform configuration:

```bash
cd infrastructure
terraform init
terraform plan   -var="prefix=<unique-prefix>"   -var="location=<azure-region>"   -var="admin_group_object_id=<aad-group-object-id>"
terraform apply   -var="prefix=<unique-prefix>"   -var="location=<azure-region>"   -var="admin_group_object_id=<aad-group-object-id>"
cd ..
```

This creates the resource group, network, AKS cluster, and ACR, and grants pull access to the AKS managed identity.

Retrieve kubeconfig and connect to the cluster:

```bash
az aks get-credentials   --resource-group <prefix>-rg   --name <prefix>-aks   --overwrite-existing
```

> Note: For Azure AD-enabled clusters, use `kubelogin`. Only use `--admin` for emergency access.

---

### 2. Build and publish container images

```bash
# Log in to ACR
az acr login --name <prefix>acr

# Backend service
cd src/backend
go test ./...
docker build -t <prefix>acr.azurecr.io/backend-app:v3 .
docker push <prefix>acr.azurecr.io/backend-app:v3
cd ../..

# Frontend app
cd src/frontend
npm install
npm run build -- --configuration production
docker build -t <prefix>acr.azurecr.io/frontend-app:v1 .
docker push <prefix>acr.azurecr.io/frontend-app:v1
cd ../..
```

If you use different image tags or registries, update the Helm values in  
`helm-charts/backend/values.yaml` and `helm-charts/frontend/values.yaml`.

---

### 3. Install Argo CD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -f argocd-cm.yaml
kubectl apply -f argocd-rbac-cm.yaml
```

Expose the Argo CD API:

- Port-forward (local):
  ```bash
  kubectl port-forward svc/argocd-server -n argocd 8443:443
  ```
- Or configure a Kubernetes Ingress or Istio VirtualService.

Retrieve the initial admin password:

```bash
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d && echo
```

---

### 4. Bootstrap GitOps applications

```bash
kubectl apply -f argocd-apps/root-app.yaml

argocd login localhost:8443 --username admin --password <password> --insecure
argocd app list
```

Argo CD will deploy:
- Istio (base, control plane, ingress gateway)
- Istio mesh configs (Gateway, VirtualService, AuthorizationPolicy)
- Vault with injector enabled
- MongoDB (Bitnami chart with metrics)
- Prometheus + Grafana stack
- Backend and frontend Helm releases

---

### 5. Configure DNS and TLS

Upload TLS certificates for the Istio Gateway:

```bash
kubectl create -n istio-system secret tls aks-tls-cert   --key <path-to-key>   --cert <path-to-cert>
```

Then map your domain (for example, `*.akssecuredemo.com`) to the ingress gateway IP:

```bash
kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

---

### 6. Inject secrets with Vault

The backend expects `MONGO_URI` via Helm values.  
In production, configure Vault to inject this secret instead.

Example setup:
1. Enable Kubernetes auth in Vault and create a role (for example, `backend-role`) bound to the backend service account.  
2. Store MongoDB credentials at `secret/data/db-creds`.  
3. Annotate the backend deployment for Vault injection.  
4. Update the deployment to read the secret from the injected file or environment variable.

---

### 7. Monitoring and scaling

Access Grafana:

```bash
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
# Username: admin
# Password: admin123
```

Check autoscaling status:

```bash
kubectl get hpa backend-hpa
```

Use `kubectl logs`, `kubectl top pod`, or Grafana dashboards to observe performance.

---

## Operations

### Verify deployment

```bash
argocd app list
argocd app get backend-app
```

### Validate Istio security

```bash
kubectl get peerauthentication -n istio-system
kubectl get authorizationpolicy aks-auth-policy -n istio-system -o yaml
```

### Test the app

Open `https://<gateway-ip-or-domain>/` in a browser or test the backend endpoint:

```bash
curl https://<gateway>/api/ping
```

---

### Teardown

Run the included script to clean up:

```bash
./scripts/teardown.sh
```

This removes Argo CD applications and destroys all Terraform-managed infrastructure.

---

## Security Notes

- The AKS API server uses Azure RBAC; no local admin users.  
- Istio enforces strict mTLS and ingress authorization.  
- Network policies limit database access to backend pods only.  
- Vault handles all secrets dynamically (no plain text credentials).  
- Prometheus and Grafana expose metrics used for autoscaling and monitoring.

---

## Next Steps

- Add CI/CD pipelines to automate image builds and Terraform validation.  
- Replace demo TLS certificates with production certificates managed by cert-manager.  
- Move sensitive Helm values into sealed secrets or ExternalSecrets linked to Vault.  
- Integrate Snyk or similar tools for IaC and container scanning.
