param(
  [int]   $LocalHttp   = 80,
  [int]   $ForwardPort = 8081,
  [string]$Namespace   = "ingress-nginx",
  [string]$Service     = "ingress-nginx-controller"
)

$netsh = "$env:WINDIR\System32\netsh.exe"
& $netsh interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport=$LocalHttp 2>$null | Out-Null

# Stop any matching kubectl port-forward
Get-CimInstance Win32_Process -Filter "Name='kubectl.exe'" |
  Where-Object {
    $_.CommandLine -match 'port-forward' -and
    $_.CommandLine -match [regex]::Escape("svc/$Service") -and
    $_.CommandLine -match [regex]::Escape("$ForwardPort:80")
  } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Write-Host "Local ingress mapping removed."
