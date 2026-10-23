#Requires -RunAsAdministrator
# Builds and registers the JellyfinDualboot Windows service. It runs as YOUR account (WSL2 distros are
# per-user, so LocalSystem can't see them) and starts Jellyfin on start, stops it cleanly on stop/shutdown.
param(
  [string]$Distro = '',
  [switch]$Auto, # start at boot (default: manual, `Start-Service JellyfinDualboot`)
  [string]$ProjectWin = (Split-Path -Parent $PSScriptRoot)
)
$name = 'JellyfinDualboot'
$bin = Join-Path $ProjectWin 'windows\bin'
$exe = Join-Path $bin 'JellyfinService.exe'
$csc = Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'

New-Item -ItemType Directory -Force $bin | Out-Null
if (Get-Service $name -ErrorAction SilentlyContinue) {
  Stop-Service $name -ErrorAction SilentlyContinue
  sc.exe delete $name | Out-Null
  Start-Sleep 2
}
& $csc /nologo /target:exe "/out:$exe" /reference:System.ServiceProcess.dll (Join-Path $PSScriptRoot 'JellyfinService.cs')
if ($LASTEXITCODE -ne 0) { throw 'compile failed' }

$cred = Get-Credential -UserName "$env:USERDOMAIN\$env:USERNAME" -Message 'Account password the service runs as (needs your WSL distros)'
& (Join-Path $PSScriptRoot 'grant-service-logon.ps1') -User $cred.UserName
$cmd = "`"$exe`" `"$ProjectWin`"" + $(if ($Distro) { " `"$Distro`"" })
New-Service -Name $name -BinaryPathName $cmd -DisplayName 'Jellyfin (dual-boot, WSL2)' `
  -Description 'Mounts the shared Jellyfin config VHDX into WSL2 and runs Jellyfin; stops cleanly on shutdown.' `
  -StartupType $(if ($Auto) { 'Automatic' } else { 'Manual' }) -Credential $cred | Out-Null

# Shutdown can take a while (container stop + unmount); give services more time before Windows kills them.
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name WaitToKillServiceTimeout -Value '90000'

Write-Host "Installed. Start-Service $name / Stop-Service $name"
