#Requires -RunAsAdministrator
# Rebuilds JellyfinService.exe in place (stops the service if running, restarts it afterwards).
# Keeps the registration and stored password, unlike install-service.ps1.
param([string]$ProjectWin = (Split-Path -Parent $PSScriptRoot))
$name = 'JellyfinDualboot'
$exe = Join-Path $ProjectWin 'windows\bin\JellyfinService.exe'
$csc = Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'

$svc = Get-Service $name -ErrorAction Stop
$wasRunning = $svc.Status -eq 'Running'
if ($svc.Status -ne 'Stopped') { Stop-Service $name }
& $csc /nologo /target:exe "/out:$exe" /reference:System.ServiceProcess.dll (Join-Path $PSScriptRoot 'JellyfinService.cs')
if ($LASTEXITCODE -ne 0) { throw 'compile failed' }
if ($wasRunning) { Start-Service $name }
Write-Host "Rebuilt $exe"
