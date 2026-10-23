#!/usr/bin/env bash
# Installs the units into /etc/systemd/system and /etc/containers/systemd. Not enabled at boot on purpose:
#   sudo systemctl start jellyfin         # attaches the VHDX, then starts the container
#   sudo systemctl stop jellyfin-config   # stops the container and detaches the VHDX
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
set -a; . ../.env; set +a
: "${MEDIA_DIR:=/mnt/XS1000}" "${TZ:=Europe/Budapest}"
[[ ${JELLYFIN_TAG:-latest} != latest ]] || echo "install.sh: warning, JELLYFIN_TAG is not pinned" >&2

sudo install -m644 jellyfin-config.service /etc/systemd/system/
sudo mkdir -p /etc/containers/systemd
sed -e "s|@MEDIA_DIR@|$MEDIA_DIR|g" -e "s|@JELLYFIN_TAG@|${JELLYFIN_TAG:-latest}|g" -e "s|@TZ@|$TZ|g" \
  jellyfin.container.in | sudo tee /etc/containers/systemd/jellyfin.container >/dev/null
sudo systemctl daemon-reload
