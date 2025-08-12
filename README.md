# Cloud Video Uploader

Cloud Video Uploader is a .NET 7 Web API for uploading videos to Azure Blob Storage.  
It’s designed to run in Kubernetes and supports both local development with Minikube + Azurite 
and production deployment on Azure Kubernetes Service (AKS) with Azure Container Registry (ACR).

---

## Live Swagger

- Cloud (AKS) - Public IP from LoadBalancer:  
  http://132.220.44.178/swagger/index.html

- Local (Minikube) – Port-forward from the service:  
  ```bash
  kubectl --context minikube -n cloudvideouploader port-forward svc/cloudvideouploader 8080:80
  # open:
  http://localhost:8080/swagger/index.html


## Key Features:
ASP.NET Core (.NET 7) Web API with Swagger/OpenAPI
Stores video uploads in Azure Blob Storage
Containerized with Docker
Local development using Azurite (Azure Storage emulator)
Kubernetes manifests for Minikube and AKS
ACR for image hosting
PowerShell deployment script for build → push → rollout
Optional local Ingress for pretty hostnames (cloudvideo.local)

------------------------------------------------------
## How It Works
API (api container) handles upload requests and streams files to Blob Storage.
Azure Blob Storage stores video data.
ACR hosts container images.
Kubernetes deploys the API with a Service for access.
Exposure:
Local: Port-forward or optional Ingress hostname
Cloud: AKS Service with type LoadBalancer for public access

## Requirements
Docker
Kubernetes CLI (kubectl)
Minikube
Azure CLI
PowerShell 7+
.NET 7 SDK

------------------------------------------------------
## Running Locally
# Using Docker only:
docker build -t cloudvideouploader .
docker run -p 8080:80 \
  -e Storage__ConnectionString="UseDevelopmentStorage=true" \
  cloudvideouploader
Swagger: http://localhost:8080/swagger/index.html

# Using Minikube:
kubectl --context minikube create ns cloudvideouploader 2>/dev/null || true
kubectl --context minikube -n cloudvideouploader apply -f k8s/
kubectl --context minikube -n cloudvideouploader port-forward svc/cloudvideouploader 8080:80

## Local Ingress (Optional)
For a cleaner local URL (http://cloudvideo.local):

# Run as Administrator
.\scripts\start-local-ingress.ps1
# browse:
http://cloudvideo.local/swagger/index.html
Stop it with:
.\scripts\stop-local-ingress.ps1

## Deployment to AKS
# The deploy.ps1 script builds the image, pushes it to ACR, and updates deployments in both Minikube and AKS.

.\scripts\deploy.ps1
# or specify your own tag
.\scripts\deploy.ps1 -TagOverride latest

Default settings:
Contexts: minikube, aks
Namespace: cloudvideouploader
Container name: api
ACR name: marinakregistry123.azurecr.io