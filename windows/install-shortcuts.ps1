# Creates "Start Jellyfin" / "Stop Jellyfin" Start menu shortcuts for the current user.
# Run once from an ELEVATED PowerShell: it also lets this user start/stop the JellyfinDualboot service
# (service ACL), so the shortcuts themselves don't need admin or a UAC prompt. Re-run after install-service.ps1
# (reinstalling resets the service ACL).
param([string]$ProjectWin = (Split-Path -Parent $PSScriptRoot))
$name = 'JellyfinDualboot'
$ctl = Join-Path $ProjectWin 'windows\service-ctl.ps1'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrator')
if ($isAdmin) {
  $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $sd = (sc.exe sdshow $name | Where-Object { $_ -match '^D:' }) -join ''
  if (-not $sd) { throw "could not read the security descriptor of $name" }
  if ($sd -notmatch [regex]::Escape($sid)) {
    # RP = start, WP = stop, plus query rights; inserted into the DACL ahead of any SACL
    $ace = "(A;;LCRPWPLORC;;;$sid)"
    $sd = if ($sd -match 'S:') { $sd -replace 'S:', "$ace`S:" } else { $sd + $ace }
    sc.exe sdset $name $sd | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'sc sdset failed' }
    Write-Host 'Granted start/stop on the service to the current user.'
  }
} else {
  Write-Warning 'Not elevated: shortcuts will be created, but start/stop will need admin until you re-run this elevated.'
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
