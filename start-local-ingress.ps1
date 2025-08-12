param(
  [string]$HostName    = "cloudvideo.local",
  [int]   $LocalHttp   = 80,
  [int]   $ForwardPort = 8081,
  [string]$Namespace   = "ingress-nginx",
  [string]$Service     = "ingress-nginx-controller",
  [string]$KubeContext = "minikube"
)

# Admin check
$wi=[Security.Principal.WindowsIdentity]::GetCurrent()
$wp=New-Object Security.Principal.WindowsPrincipal($wi)
if(-not $wp.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
  Write-Error "Please run this script as Administrator."; exit 1
}

# Preflight
kubectl version --client *> $null || (Write-Error "kubectl not found"; exit 1)
kubectl --context $KubeContext -n $Namespace get svc $Service *> $null || (Write-Error "Service $Namespace/$Service not found"; exit 1)

# Guard local port 80
if (Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $LocalHttp -ErrorAction SilentlyContinue) {
  Write-Error "Local port $LocalHttp is already in use."; exit 1
}

# 1) Ensure port-forward is running on 127.0.0.1:$ForwardPort
if(-not (Test-NetConnection 127.0.0.1 -Port $ForwardPort).TcpTestSucceeded){
  Start-Process -FilePath "kubectl" -WindowStyle Minimized `
    -ArgumentList @("--context",$KubeContext,"-n",$Namespace,"port-forward","svc/$Service","$ForwardPort:80")
  1..10 | ForEach-Object { if((Test-NetConnection 127.0.0.1 -Port $ForwardPort).TcpTestSucceeded){break}; Start-Sleep 1 }
}

# 2) Map local 80 -> ForwardPort via portproxy
$netsh = "$env:WINDIR\System32\netsh.exe"
Start-Service iphlpsvc -ErrorAction SilentlyContinue | Out-Null
& $netsh interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport=$LocalHttp 2>$null | Out-Null
& $netsh interface portproxy add    v4tov4 listenaddress=127.0.0.1 listenport=$LocalHttp connectaddress=127.0.0.1 connectport=$ForwardPort

# 3) Ensure hosts entries
$hosts = "$env:WINDIR\System32\drivers\etc\hosts"
$lines = @(); if(Test-Path $hosts){ $lines = Get-Content $hosts -ErrorAction SilentlyContinue }
if($lines -notmatch '^\s*127\.0\.0\.1\s+localhost'){ Add-Content $hosts "127.0.0.1`tlocalhost" }
if($lines -notmatch '^\s*::1\s+localhost'){          Add-Content $hosts "::1`tlocalhost" }
(Get-Content $hosts) | Where-Object {$_ -notmatch '\scloudvideo\.local(\s|$)'} | Set-Content $hosts -Encoding ASCII
Add-Content $hosts ("127.0.0.1`t{0}" -f $HostName)
& "$env:WINDIR\System32\ipconfig.exe" /flushdns | Out-Null

# 4) Smoke test
try{
  $r = Invoke-WebRequest ("http://{0}/health" -f $HostName) -UseBasicParsing -TimeoutSec 5
  Write-Host ("OK: {0} {1}" -f $r.StatusCode, $r.StatusDescription)
}catch{
  Write-Warning "Health check failed. Is the p
