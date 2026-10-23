#Requires -RunAsAdministrator
$name = 'JellyfinDualboot'
if (Get-Service $name -ErrorAction SilentlyContinue) {
  Stop-Service $name -ErrorAction SilentlyContinue
  sc.exe delete $name
}
