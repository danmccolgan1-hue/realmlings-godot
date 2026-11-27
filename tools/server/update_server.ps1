# Send a new server build to the Droplet and restart the server (docs/SERVER.md, "Updating").
# Run from the project folder in PowerShell:   .\tools\server\update_server.ps1 -Ip 203.0.113.10
# Export the Linux build first. It may be one file (Realmlings.x86_64, data inside) or two (Realmlings.x86_64 and
# Realmlings.pck), in build\server or in the project folder itself: the script finds them.
param([Parameter(Mandatory = $true)][string]$Ip)

$dir = $null
foreach ($d in @("build\server", ".")) { if (Test-Path "$d\Realmlings.x86_64") { $dir = $d; break } }
if (-not $dir) { Write-Error "No Realmlings.x86_64 found (in build\server or here): export the Linux build in Godot first."; exit 1 }
$files = @("$dir\Realmlings.x86_64")
if (Test-Path "$dir\Realmlings.pck") { $files += "$dir\Realmlings.pck" }
Write-Host "Uploading $($files -join ', ') ..."

ssh "root@$Ip" "mkdir -p /home/realmlings/upload"
scp @files "root@${Ip}:/home/realmlings/upload/"
# (every Realmlings server on the Droplet: the first, and any realmlings@<port> ones)
ssh "root@$Ip" "units=`$(systemctl list-units --all --plain --no-legend 'realmlings*' | awk '{print `$1}' | grep -E '^realmlings(@[0-9]+)?\.service$'); systemctl stop `$units; rm -f /home/realmlings/server/Realmlings.pck; mv /home/realmlings/upload/* /home/realmlings/server/; chmod +x /home/realmlings/server/Realmlings.x86_64; chown -R realmlings: /home/realmlings; systemctl start `$units; sleep 2; systemctl --no-pager --lines=0 status `$units"
