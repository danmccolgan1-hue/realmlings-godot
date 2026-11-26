# Send a new server build to the Droplet and restart the server (docs/SERVER.md, "Updating").
# Run from the project folder in PowerShell:   .\tools\server\update_server.ps1 -Ip 203.0.113.10
# Export the "Linux Server" preset first (Project > Export), so build\server\Realmlings.x86_64 is the new build.
param([Parameter(Mandatory = $true)][string]$Ip)

$build = "build\server\Realmlings.x86_64"
if (-not (Test-Path $build)) { Write-Error "No $build yet: export the Linux Server preset in Godot first."; exit 1 }

scp $build "root@${Ip}:/home/realmlings/server/Realmlings.x86_64.new"
ssh "root@$Ip" "systemctl stop realmlings; mv /home/realmlings/server/Realmlings.x86_64.new /home/realmlings/server/Realmlings.x86_64; chmod +x /home/realmlings/server/Realmlings.x86_64; chown realmlings: /home/realmlings/server/Realmlings.x86_64; systemctl start realmlings; systemctl --no-pager status realmlings | head -5"
