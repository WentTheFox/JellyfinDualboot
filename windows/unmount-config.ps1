#Requires -RunAsAdministrator
# Stops Jellyfin and detaches the shared VHDX from WSL2. Run before rebooting into Linux.
param(
  [string]$Distro = '',
  [string]$ProjectWin = (Split-Path -Parent $PSScriptRoot)
)
$vhdx = Join-Path $ProjectWin 'data\jellyfin-config.vhdx'
$drive = $ProjectWin.Substring(0, 1).ToLower()
$rest = $ProjectWin.Substring(3) -replace '\\', '/'
$dArg = if ($Distro) { @('-d', $Distro) } else { @() }

wsl @dArg -- bash -lc "cd /mnt/$drive/$rest && ./jf down"
wsl --unmount $vhdx
