# Start or stop the JellyfinDualboot service and show the result. Used by the Start menu shortcuts
# (see install-shortcuts.ps1), which need no elevation once the service ACL has been granted.
param([Parameter(Mandatory)][ValidateSet('start', 'stop')][string]$Action)
$name = 'JellyfinDualboot'
try {
  if ($Action -eq 'start') {
    Write-Host 'Starting Jellyfin (mounting the config volume, this takes a few seconds)...'
    Start-Service $name -ErrorAction Stop
    Write-Host 'Jellyfin is running: http://127.0.0.1:8096' -ForegroundColor Green
  } else {
    Write-Host 'Stopping Jellyfin (stopping the container, detaching the config volume)...'
    Stop-Service $name -ErrorAction Stop
    Write-Host 'Jellyfin stopped, the config volume is detached.' -ForegroundColor Green
  }
  Start-Sleep 3
} catch {
  Write-Host "Failed: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host 'Details: windows\bin\service.log'
  Read-Host 'Press Enter to close'
}
