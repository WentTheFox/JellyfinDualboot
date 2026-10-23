#Requires -RunAsAdministrator
# Grants "Log on as a service" (SeServiceLogonRight) to an account; services can't start as it without.
param([string]$User = "$env:USERDOMAIN\$env:USERNAME")
$ErrorActionPreference = 'Stop'
$User = $User -replace '^\.\\', "$env:COMPUTERNAME\"
$sid = (New-Object Security.Principal.NTAccount($User)).Translate([Security.Principal.SecurityIdentifier]).Value
$cfg = Join-Path $env:TEMP 'jf-secpol.inf'
$db = Join-Path $env:TEMP 'jf-secpol.sdb'
secedit /export /cfg $cfg /areas USER_RIGHTS | Out-Null
$lines = Get-Content $cfg
if ($lines -match "SeServiceLogonRight.*\*$sid") { Write-Host "$User already has the right"; return }
$lines = $lines | ForEach-Object { if ($_ -match '^SeServiceLogonRight') { "$_,*$sid" } else { $_ } }
Set-Content $cfg $lines -Encoding Unicode
secedit /configure /db $db /cfg $cfg /areas USER_RIGHTS | Out-Null
Remove-Item $cfg, $db -ErrorAction SilentlyContinue
Write-Host "Granted Log on as a service to $User"
