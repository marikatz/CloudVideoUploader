param(
  [string]$AcrName     = "marinakregistry123",
  [string]$ImageName   = "cloudvideouploader",
  [string]$Namespace   = "cloudvideouploader",
  [string]$Deployment  = "cloudvideouploader",
  [string]$Container   = "api",
  [string[]]$Contexts  = @("minikube","aks"),   # <-- fixed names
  [string]$TagOverride = ""
)

$ErrorActionPreference = "Stop"

# Tag = timestamp + short git sha (or override)
$ts  = (Get-Date).ToString("yyyyMMdd-HHmm")
$sha = (git rev-parse --short HEAD 2>$null); if (-not $sha) { $sha = "dev" }
$tag = [string]::IsNullOrWhiteSpace($TagOverride) ? "$ts-$sha" : $TagOverride

$registry = "$AcrName.azurecr.io"
$imageRef = "$registry/$ImageName:$tag"

Write-Host ">> Building $imageRef"
docker build -t "$imageRef" .

Write-Host ">> az acr login ($AcrName)"
az acr login --name "$AcrName" | Out-Null

Write-Host ">> Pushing $imageRef"
docker push "$imageRef"

# Try to fetch ACR admin creds (used for minikube pull secret)
$acrCred = $null
try {
  az acr update --name "$AcrName" --admin-enabled true | Out-Null
  $acrCred = az acr credential show --name "$AcrName" --query "{u:username,p:passwords[0].value}" -o json | ConvertFrom-Json
} catch {
  Write-Host "!! Could not fetch ACR admin credentials. If minikube pull fails, create the secret manually."
}

# JSON patches (container name is variable)
$patchSecret = @'
{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"acr-pull"}]}}}}
'@

$patchPolicyAlways = @"
{"spec":{"template":{"spec":{"containers":[{"name":"$Container","imagePullPolicy":"Always"}]}}}}
"@

foreach ($ctx in $Contexts) {
  Write-Host "`n>> Context: $ctx"

  # Ensure namespace exists
  if (-not (kubectl --context "$ctx" get ns "$Namespace" *> $null)) {
    kubectl --context "$ctx" create ns "$Namespace" | Out-Null
  }

  # Guard: only patch if Deployment exists
  $deployExists = $true
  kubectl --context "$ctx" -n "$Namespace" get deploy/"$Deployment" *> $null
  if ($LASTEXITCODE -ne 0) { $deployExists = $false }

  if ($ctx -eq "minikube") {
    # Create/refresh acr-pull secret in minikube
    if ($acrCred -ne $null) {
      Write-Host ">> (minikube) ensuring acr-pull secret"
      kubectl --context "$ctx" -n "$Namespace" delete secret acr-pull *> $null
      kubectl --context "$ctx" -n "$Namespace" create secret docker-registry acr-pull `
        --docker-server="$registry" `
        --docker-username="$($acrCred.u)" `
        --docker-password="$($acrCred.p)" `
        --docker-email="devnull@example.com" | Out-Null

      if ($deployExists) {
        kubectl --context "$ctx" -n "$Namespace" patch deploy/"$Deployment" -p $patchSecret
      }
    } else {
      Write-Host "!! Skipping secret creation for minikube (no ACR admin creds)."
    }
  }

  if ($deployExists) {
    kubectl --context "$ctx" -n "$Namespace" patch deploy/"$Deployment" -p $patchPolicyAlways
  }

  # Set new image (creates new RS/rollout if Deployment exists)
  Write-Host ">> Set image on $Deployment/$Container -> $imageRef"
  kubectl --context "$ctx" -n "$Namespace" set image deployment/"$Deployment" `
    "$Container=$imageRef"

  # Wait for rollout (will fail fast if no Deployment)
  kubectl --context "$ctx" -n "$Namespace" rollout status deployment/"$Deployment"
}

Write-Host "`n✅ Deployed $imageRef to: $($Contexts -join ', ')"
Write-Host "Tip: Local test -> kubectl --context minikube -n $Namespace port-forward svc/$Deployment 8080:80  # then open http://localhost:8080/swagger"
