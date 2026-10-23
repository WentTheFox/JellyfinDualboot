#!/usr/bin/env bash
# Run inside the WSL2 distro (needs systemd=true in /etc/wsl.conf): installs a unit that stops the
# Jellyfin container when the distro shuts down.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."
sed -e "s/@UID@/$(id -u)/g" -e "s/@USER@/$(id -un)/g" systemd/jellyfin-wsl-stop.service.in \
  | sudo tee /etc/systemd/system/jellyfin-wsl-stop.service >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable --now jellyfin-wsl-stop.service
systemctl status jellyfin-wsl-stop.service --no-pager | head -5
