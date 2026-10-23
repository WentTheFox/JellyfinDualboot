#Requires -RunAsAdministrator
# Mounts the shared ext4 VHDX into WSL2 at /mnt/wsl/jellyfin-config, then starts Jellyfin.
param(
  [string]$Distro = '',
  [string]$ProjectWin = (Split-Path -Parent $PSScriptRoot)
)
$vhdx = Join-Path $ProjectWin 'data\jellyfin-config.vhdx'
if (-not (Test-Path $vhdx)) { throw "$vhdx not found" }

wsl --mount --vhd $vhdx --name jellyfin-config --type ext4
if ($LASTEXITCODE -ne 0) { throw 'wsl --mount failed' }

$drive = $ProjectWin.Substring(0, 1).ToLower()
$rest = $ProjectWin.Substring(3) -replace '\\', '/'
$dArg = if ($Distro) { @('-d', $Distro) } else { @() }
wsl @dArg -- bash -lc "cd /mnt/$drive/$rest && ./jf up"
