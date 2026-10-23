# Creates "Start Jellyfin" / "Stop Jellyfin" Start menu shortcuts for the current user, and lets this user
# start/stop the JellyfinDualboot service (service ACL), so the shortcuts need no admin or UAC prompt.
# Relaunches itself elevated (one UAC prompt) if needed. Re-run after install-service.ps1
# (reinstalling resets the service ACL).
param(
  [string]$ProjectWin = (Split-Path -Parent $PSScriptRoot),
  [switch]$Elevated # set on the self-relaunch below
)
$name = 'JellyfinDualboot'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrator')) {
  $ps = (Get-Process -Id $PID).Path
  Start-Process $ps -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -ProjectWin `"$ProjectWin`" -Elevated"
  return
}

try {
  $ctl = Join-Path $ProjectWin 'windows\service-ctl.ps1'

  $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $sd = (sc.exe sdshow $name | Where-Object { $_ -match '^D:' }) -join ''
  if (-not $sd) { throw "could not read the security descriptor of $name (is the service installed?)" }
  if ($sd -notmatch [regex]::Escape($sid)) {
    # RP = start, WP = stop, plus query rights; inserted into the DACL ahead of any SACL
    $ace = "(A;;LCRPWPLORC;;;$sid)"
    $sd = if ($sd -match 'S:') { $sd -replace 'S:', "$ace`S:" } else { $sd + $ace }
    sc.exe sdset $name $sd | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'sc sdset failed' }
    Write-Host 'Granted start/stop on the service to the current user.'
  } else {
    Write-Host 'Service access already granted.'
  }

  $dir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Jellyfin (dual-boot)'
  New-Item -ItemType Directory -Force $dir | Out-Null
  $shell = New-Object -ComObject WScript.Shell
  foreach ($a in 'start', 'stop') {
    $lnk = $shell.CreateShortcut((Join-Path $dir ("$((Get-Culture).TextInfo.ToTitleCase($a)) Jellyfin.lnk")))
    $lnk.TargetPath = 'powershell.exe'
    $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ctl`" -Action $a"
    $lnk.WorkingDirectory = $ProjectWin
    $lnk.Description = "$a the Jellyfin (dual-boot, WSL2) service"
    $lnk.WindowStyle = 1
    $lnk.Save()
  }
  Write-Host "Shortcuts created in: $dir"
} catch {
  Write-Host "Failed: $($_.Exception.Message)" -ForegroundColor Red
} finally {
  if ($Elevated) { Read-Host 'Press Enter to close' }
}
