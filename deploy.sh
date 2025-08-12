#!/usr/bin/env bash
set -euo pipefail

# Always run from the script's own folder
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ====== CONFIG ======
ACR_NAME="marinakregistry123"
IMAGE_NAME="cloudvideouploader"
NAMESPACE="cloudvideouploader"
DEPLOYMENT="cloudvideouploader"
CONTAINER="api"
CONTEXTS=("minikube" "aks-cloudvideo")   # kubeconfig context names

# Optional: pass a tag override as the first argument. Else: timestamp + short git sha
TAG_OVERRIDE="${1:-}"

# ====== COMPUTED ======
TS="$(date +%Y%m%d-%H%M)"
SHA="$(git rev-parse --short HEAD 2>/dev/null || echo dev)"
TAG="${TAG_OVERRIDE:-${TS}-${SHA}}"
REGISTRY="${ACR_NAME}.azurecr.io"
IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${TAG}"

# ====== PRECHECKS ======
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }
need docker
need az
need kubectl

# ====== BUILD & PUSH ======
echo ">> Building ${IMAGE_REF}"
docker build -t "${IMAGE_REF}" .

echo ">> Logging into ACR: ${ACR_NAME}"
az acr login --name "${ACR_NAME}" >/dev/null

echo ">> Pushing ${IMAGE_REF}"
docker push "${IMAGE_REF}"

# Fetch ACR admin creds (for minikube pull secret). Harmless for AKS.
echo ">> Ensuring ACR admin creds are enabled (dev convenience)"
az acr update --name "${ACR_NAME}" --admin-enabled true >/dev/null
ACR_USER="$(az acr credential show --name "${ACR_NAME}" --query username -o tsv)"
ACR_PASS="$(az acr credential show --name "${ACR_NAME}" --query passwords[0].value -o tsv)"

# ====== DEPLOY PER CONTEXT ======
for CTX in "${CONTEXTS[@]}"; do
  echo
  echo ">> Context: ${CTX}"

  # Ensure namespace exists
  if ! kubectl --context "$CTX" get ns "${NAMESPACE}" >/dev/null 2>&1; then
    kubectl --context "$CTX" create ns "${NAMESPACE}"
  fi

  # Minikube needs a pull secret to ACR (AKS should be attached to ACR via az aks update --attach-acr)
  if [[ "$CTX" == "minikube" ]]; then
    echo ">> (minikube) creating/updating ACR pull secret"
    kubectl --context "$CTX" -n "${NAMESPACE}" delete secret acr-pull --ignore-not-found
    kubectl --context "$CTX" -n "${NAMESPACE}" create secret docker-registry acr-pull \
      --docker-server="${REGISTRY}" \
      --docker-username="${ACR_USER}" \
      --docker-password="${ACR_PASS}" \
      --docker-email="devnull@example.com"

    echo ">> (minikube) patching Deployment to use imagePullSecrets + pull Always"
    kubectl --context "$CTX" -n "${NAMESPACE}" patch deploy/"${DEPLOYMENT}" \
      -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"acr-pull"}]}}}}' || true

    kubectl --context "$CTX" -n "${NAMESPACE}" patch deploy/"${DEPLOYMENT}" \
      -p '{"spec":{"template":{"spec":{"containers":[{"name":"'"${CONTAINER}"'","imagePullPolicy":"Always"}]}}}}' || true
  fi

  echo ">> Updating image to ${IMAGE_REF}"
  kubectl --context "$CTX" -n "${NAMESPACE}" set image deployment/"${DEPLOYMENT}" "${CONTAINER}=${IMAGE_REF}"

  echo ">> Waiting for rollout in ${CTX}"
  kubectl --context "$CTX" -n "${NAMESPACE}" rollout status deployment/"${DEPLOYMENT}"
done

echo
echo "✅ Deployed ${IMAGE_REF} to: ${CONTEXTS[*]}"
echo "Tip (local): kubectl --context minikube -n ${NAMESPACE} port-forward svc/${DEPLOYMENT} 8080:80  → http://localhost:8080/"
