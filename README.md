# Security-Focused AKS Deployment

This repository provisions an Azure Kubernetes Service (AKS) environment that demonstrates a secure, GitOps-driven deployment pipeline. Infrastructure is codified with Terraform, applications are packaged as Helm charts, Istio provides zero-trust networking, HashiCorp Vault manages application secrets, and Argo CD continuously reconciles desired state from Git.

---

## Architecture Overview

| Layer | Components | Notes |
| --- | --- | --- |
| Azure infrastructure | Resource group, virtual network, AKS cluster, Azure Container Registry (ACR) | Defined in `infrastructure/` Terraform modules. AKS uses managed identity and Azure RBAC integration. 【F:infrastructure/main.tf†L1-L66】【F:infrastructure/main.tf†L67-L92】 |
| GitOps control plane | Argo CD core installation plus custom `argocd-cm.yaml` and `argocd-rbac-cm.yaml` | Configures auto-sync, namespace creation, and admin RBAC. 【F:argocd-apps/root-app.yaml†L1-L25】【F:argocd-cm.yaml†L1-L57】 |
| Service mesh | Istio base, control plane, ingress gateway, and mesh policies | Delivered through Argo CD applications that track official Istio Helm charts and local Istio manifests. 【F:argocd-apps/istio-base-app.yaml†L1-L24】【F:istio-config/peer-auth.yaml†L1-L8】 |
| Workloads | Angular frontend, Go backend API, Bitnami MongoDB, Vault server, kube-prometheus-stack | Backend/Frontend charts in `helm-charts/`, third-party charts referenced from vendors, Vault injector enabled for secret distribution. 【F:helm-charts/backend/templates/deployment.yaml†L1-L54】【F:argocd-apps/vault-app.yaml†L1-L24】 |
| Security controls | Istio strict mTLS, authorization policy, network policies, Vault injector, Kubernetes RBAC | `istio-config/` enforces mesh-wide mTLS and gateway policy; backend NetworkPolicy restricts database access. 【F:istio-config/auth-policy.yaml†L1-L28】【F:helm-charts/backend/templates/networkpolicy.yaml†L1-L16】 |
| Observability | kube-prometheus-stack, Grafana credentials, HPA metrics | Monitoring namespace managed through Argo CD with custom values. 【F:argocd-apps/monitoring-app.yaml†L1-L24】 |

---

## Repository Layout

```
.
├── infrastructure/          # Terraform for Azure RG, VNet, AKS, ACR, role assignments
├── argocd-apps/             # Argo CD Application definitions for GitOps bootstrapping
├── argocd-cm.yaml           # Argo CD ConfigMap overrides (resource exclusions, RBAC defaults)
├── argocd-rbac-cm.yaml      # Argo CD RBAC policy bindings
├── helm-charts/
│   ├── backend/             # Go API Helm chart (Istio injection, MongoDB access policy)
│   └── frontend/            # Angular static site Helm chart served via NGINX
├── istio-config/            # Gateway, VirtualService, mTLS, and authorization policy manifests
├── src/
│   ├── backend/             # Go backend service source code
│   └── frontend/            # Angular frontend project
├── scripts/teardown.sh      # Destroys Argo CD apps and Terraform infrastructure
└── guide.txt                # Extended implementation notes and rationale
```

---

## Prerequisites

1. **Azure access**
   - Azure subscription with permissions to create resource groups, networks, AKS, and ACR.
   - Azure Active Directory group object ID for AKS admin access (see `infrastructure/variables.tf`). 【F:infrastructure/variables.tf†L1-L15】

2. **Local tooling**
   - Terraform >= 1.5
   - Azure CLI >= 2.50
   - kubectl matching the AKS version (`az aks install-cli` recommended)
   - Helm >= 3.12
   - Docker or alternative OCI-compliant image builder
   - Node.js 18 LTS + npm (build Angular frontend)
   - Go 1.21 (build backend API)

3. **Optional utilities**
   - jq, make, Snyk CLI (referenced in `guide.txt` for security scanning)
   - kubelogin for Azure AD auth with `kubectl`

---

## Deployment Workflow

### 1. Configure environment

```bash
# Authenticate to Azure and select the subscription
az login
az account set --subscription <subscription-id>

# Clone and enter the repository
git clone https://github.com/Y2not2nd/Security-Focused-AKS-Deployment-Kubernets.git
cd Security-Focused-AKS-Deployment-Kubernets
```

Update Terraform variables as needed:

```bash
cd infrastructure
# Optionally override defaults
terraform init
terraform plan \
  -var="prefix=<unique-prefix>" \
  -var="location=<azure-region>" \
  -var="admin_group_object_id=<aad-group-object-id>"
terraform apply \
  -var="prefix=<unique-prefix>" \
  -var="location=<azure-region>" \
  -var="admin_group_object_id=<aad-group-object-id>"
cd ..
```

Terraform provisions the resource group, VNet, AKS cluster, and ACR, then grants the cluster managed identity permission to pull from ACR. 【F:infrastructure/main.tf†L1-L92】

Retrieve kubeconfig and log into the cluster via Azure AD:

```bash
az aks get-credentials \
  --resource-group <prefix>-rg \
  --name <prefix>-aks \
  --overwrite-existing
```

> **Note:** When using Azure AD-enabled clusters, install `kubelogin` and run `az aks get-credentials --admin` only for break-glass scenarios.

### 2. Build and publish container images

1. Sign in to ACR:
   ```bash
   az acr login --name <prefix>acr
   ```
2. Build and push the backend service:
   ```bash
   cd src/backend
   go test ./...
   docker build -t <prefix>acr.azurecr.io/backend-app:v3 .
   docker push <prefix>acr.azurecr.io/backend-app:v3
   cd ../..
   ```
3. Build and push the frontend image (Angular + NGINX):
   ```bash
   cd src/frontend
   npm install
   npm run build -- --configuration production
   docker build -t <prefix>acr.azurecr.io/frontend-app:v1 .
   docker push <prefix>acr.azurecr.io/frontend-app:v1
   cd ../..
   ```

If you use alternative tags or registries, update the Helm values before syncing Argo CD (`helm-charts/backend/values.yaml`, `helm-charts/frontend/values.yaml`). 【F:helm-charts/backend/values.yaml†L1-L25】【F:helm-charts/frontend/values.yaml†L1-L13】

### 3. Install Argo CD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -f argocd-cm.yaml
kubectl apply -f argocd-rbac-cm.yaml
```

Expose the Argo CD API (choose one):

- **Port-forward (development):**
  ```bash
  kubectl port-forward svc/argocd-server -n argocd 8443:443
  ```
- **Ingress / Load balancer:** configure a Kubernetes Ingress or Istio VirtualService as required.

Retrieve the initial admin password:
```bash
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d && echo
```

### 4. Bootstrap GitOps applications

1. Create the root application that recursively applies everything under `argocd-apps/`:
   ```bash
   kubectl apply -f argocd-apps/root-app.yaml
   ```
2. Allow Argo CD to sync. Verify status:
   ```bash
   argocd login localhost:8443 --username admin --password <password> --insecure
   argocd app list
   ```

Argo CD will install:
- Istio base, control plane, and ingress gateway (version 1.22.8) with strict mTLS. 【F:argocd-apps/istio-cp-app.yaml†L1-L22】【F:istio-config/peer-auth.yaml†L1-L8】
- Istio mesh configuration (`Gateway`, `VirtualService`, `AuthorizationPolicy`, `PeerAuthentication`). 【F:istio-config/gateway.yaml†L1-L33】【F:istio-config/auth-policy.yaml†L1-L28】
- Vault with injector sidecar enabled. 【F:argocd-apps/vault-app.yaml†L1-L24】
- Bitnami MongoDB with authentication and metrics. 【F:argocd-apps/mongodb-app.yaml†L1-L26】
- kube-prometheus-stack with a preset Grafana admin password (`admin123`). 【F:argocd-apps/monitoring-app.yaml†L1-L24】
- Backend and frontend Helm releases defined in this repository. 【F:argocd-apps/backend-app.yaml†L1-L25】【F:argocd-apps/frontend-app.yaml†L1-L24】

### 5. Configure DNS and TLS

1. Upload certificates referenced by the Istio `Gateway` (`credentialName: aks-tls-cert`). 【F:istio-config/gateway.yaml†L14-L30】
   ```bash
   kubectl create -n istio-system secret tls aks-tls-cert \
     --key <path-to-key> \
     --cert <path-to-cert>
   ```
2. Map your domain (e.g., `*.akssecuredemo.com`) to the external IP of the Istio ingress gateway:
   ```bash
   kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
   ```

### 6. Inject application secrets with Vault

The backend deployment expects `MONGO_URI` via Helm values. For production-grade secret delivery, configure Vault injector policies to template the Mongo connection string to `/vault/secrets/db-creds.txt`, then adjust the Helm chart to read from the mounted file or set `env.extra` with a `valueFrom` secret reference.

Sample policy steps (see `guide.txt` for a complete walkthrough):

1. Enable Kubernetes auth in Vault and create a role (`backend-role`) bound to the backend service account.
2. Store the MongoDB URI at `secret/data/db-creds`.
3. Annotate the backend deployment with Vault injector metadata (already templated via `podAnnotations`). 【F:helm-charts/backend/values.yaml†L27-L30】
4. Update the deployment to consume the rendered file or exported environment variable before releasing.

### 7. Observability and scaling

- Access Grafana:
  ```bash
  kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
  # username: admin / password: admin123
  ```
- Monitor backend autoscaling via `kubectl get hpa backend-hpa`. HPA rendering is optional and governed by `hpa.enabled`. 【F:helm-charts/backend/templates/hpa.yaml†L1-L19】
- Use `kubectl logs`, `kubectl top pod`, or Grafana dashboards to inspect runtime behavior.

---

## Operations

### Verifying the deployment

1. Confirm Argo CD applications are healthy:
   ```bash
   argocd app list
   argocd app get backend-app
   ```
2. Validate Istio security:
   ```bash
   kubectl get peerauthentication -n istio-system
   kubectl get authorizationpolicy aks-auth-policy -n istio-system -o yaml
   ```
3. Exercise the demo application:
   - Browse to `https://<gateway-ip-or-domain>/` for the frontend UI.
   - Use the UI button or curl `https://<gateway>/api/ping` to reach the backend. The MongoDB counter increments on each call (see `src/backend/main.go`). 【F:src/backend/main.go†L1-L62】

### Maintenance and teardown

Run the provided script to remove all Argo CD-managed workloads and destroy Azure infrastructure:

```bash
./scripts/teardown.sh
```

The script validates prerequisites, deletes Argo CD applications, then runs `terraform destroy -auto-approve`. 【F:scripts/teardown.sh†L1-L67】

### Troubleshooting tips

- **Terraform binary missing:** Install Terraform locally if commands fail (`terraform init` or `terraform apply`).
- **Argo CD sync errors:** Inspect Application events (`kubectl describe application <name> -n argocd`).
- **Vault injector issues:** Ensure pods carry the proper annotations and the Vault Injector webhook is running.
- **Istio routing problems:** Confirm the `VirtualService` hosts align with your domain and the TLS secret exists.
- **MongoDB connectivity:** Validate network policy labels and that the backend pods resolve `mongodb.default.svc`. 【F:helm-charts/backend/templates/networkpolicy.yaml†L1-L16】

---

## Security Considerations

- AKS API server is restricted through Azure RBAC; local Kubernetes admin accounts remain disabled. 【F:infrastructure/main.tf†L33-L52】
- Istio enforces STRICT mTLS and explicit authorization for ingress traffic. 【F:istio-config/peer-auth.yaml†L1-L8】【F:istio-config/auth-policy.yaml†L1-L28】
- Network policies limit MongoDB ingress to backend pods, reducing lateral movement risk. 【F:helm-charts/backend/templates/networkpolicy.yaml†L1-L16】
- Vault provides dynamic secret injection; remove plaintext credentials from Helm values before production usage.
- kube-prometheus-stack surfaces metrics required by the backend HPA and service mesh dashboards. 【F:argocd-apps/monitoring-app.yaml†L1-L24】

---

## Next Steps

- Integrate CI pipelines to automate image builds and `terraform plan` checks.
- Replace demo certificates with production-grade TLS managed by cert-manager.
- Externalize sensitive Helm values into sealed secrets or ExternalSecrets referencing Vault.
- Automate Snyk IaC and container scans as described in `guide.txt`.
