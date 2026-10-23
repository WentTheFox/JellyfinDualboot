# JellyfinDualboot

One Jellyfin server and config shared between CachyOS and Windows (WSL2) on a dual-boot machine,
transcoding on the NVIDIA GPU, with media on a Raspberry Pi share.

## How it works

- `/config` and `/cache` live on an **ext4 filesystem inside `data/jellyfin-config.vhdx`** (stored on D:).
  SQLite therefore never touches NTFS (ntfs-3g and Windows' 9p mounts have unreliable locking).
  Linux attaches the VHDX with `qemu-nbd`; Windows mounts it into WSL2 with `wsl --mount --vhd`.
- Media is bind-mounted **read-only at `/media`** on both sides, so library paths (and therefore item IDs
  and watch history) are identical whichever OS is booted.
- **Only one OS runs the server at a time** (they are different boots). Always stop the server and
  detach the volume before rebooting.
- Linux: rootful podman, supervised by systemd via a Quadlet, running as uid 1000.
  WSL2: rootless podman through `compose.yml`, where container root maps to uid 1000, so file
  ownership on the shared volume matches.

```
compose.yml                      shared/WSL2 container definition
jf                               helper script (setup/up/down/attach/detach/start/stop/status)
.env.example                     settings: image tag, timezone, media path
systemd/jellyfin.container.in    Linux Quadlet template (rendered by install.sh from .env)
systemd/jellyfin-config.service  attaches and mounts the VHDX
systemd/install.sh               installs both into /etc
windows/*.ps1                    mount/unmount the VHDX in WSL2 and start/stop Jellyfin
data/                            jellyfin-config.vhdx (git-ignored)
```

## Requirements

- Linux: `podman`, `podman-compose`, `nvidia-container-toolkit`, `qemu-img`/`qemu-nbd` (qemu-base),
  the `nbd` kernel module, the NVIDIA driver, and a media share mounted at `MEDIA_DIR`.
- Windows: WSL2 with a distro whose default user has uid 1000, the NVIDIA Windows driver (WSL2 GPU
  support), and Windows Fast Startup **disabled** (otherwise D: can stay marked dirty and mount
  read-only on Linux).

## Setup: CachyOS (once)

```sh
sudo pacman -S podman podman-compose nvidia-container-toolkit qemu-base
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml   # redo after NVIDIA driver updates

cp .env.example .env     # set MEDIA_DIR, TZ and pin JELLYFIN_TAG (see below)
./jf setup               # creates the VHDX if missing, formats ext4, mounts it at /mnt/jellyfin-config
./jf down                # detach again, systemd takes over from here
bash systemd/install.sh
```

Pin `JELLYFIN_TAG` in `.env` to an exact dated tag (e.g. `12.3.20261023-013714`; `latest` is only for the
first pull). Both OSes pull their own image and a Jellyfin database migration can't be undone, so a
version mismatch between the sides can leave one unable to start. Update both sides together.

## Daily use: CachyOS

```sh
sudo systemctl start jellyfin-stack.target   # attaches the VHDX, then starts the container
sudo systemctl stop jellyfin-stack.target    # stops the container, then detaches the VHDX (before rebooting)
```

The units are intentionally **not enabled at boot**. systemd restarts the container if it crashes. (`stop jellyfin` alone only stops the container and leaves
the volume attached.)
Open <http://localhost:8096>. Add libraries as `/media/...` and pick NVIDIA NVENC under
Dashboard, Playback, Transcoding. After editing `.env` re-run `systemd/install.sh`. Don't mix
`./jf up` with the systemd units on Linux (same container name).

## Setup: Windows (once)

1. Inside the WSL2 distro: install podman, podman-compose and nvidia-container-toolkit, then
   `sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml`.
2. Mount the Pi share inside WSL2 at the **same `MEDIA_DIR`** as on Linux (sshfs or NFS).
3. The project lives on D:, so `.env` is already shared. Check it has the same `JELLYFIN_TAG`.
4. Make sure the distro's default user is uid 1000: `id -u`.

## Daily use: Windows

From an elevated PowerShell:

```powershell
.\windows\mount-config.ps1      # wsl --mount --vhd ..., then ./jf up in WSL2
.\windows\unmount-config.ps1    # ./jf down, then wsl --unmount (before rebooting to Linux)
```

### Optional: Windows service

```powershell
.\windows\install-service.ps1 [-Auto] [-Distro Debian]   # builds + registers, asks for your account password
Start-Service JellyfinDualboot    # mount-config.ps1
Stop-Service JellyfinDualboot     # unmount-config.ps1 (also runs on Windows shutdown/restart)
.\windows\uninstall-service.ps1
```

It runs as your account (WSL2 distros are per-user) and holds the distro open while running. `-Auto`
starts it at boot; the default is manual, so booting Windows doesn't claim the volume unless you want it.
If the distro goes away underneath it (`wsl --shutdown`, crash), the service notices and stops itself
(log: `windows\bin\service.log`). To also stop the container cleanly in that case, run once inside WSL2:
`bash windows/install-wsl-hook.sh` (a systemd unit that runs `podman stop` before the distro shuts down).
Rebuild after editing `JellyfinService.cs` with `.windowsPdate-service.ps1`.
Shutdown waits up to 90 s (`WaitToKillServiceTimeout`) for the container to stop and the VHDX to detach.

Pass `-Distro <name>` if your default WSL distro isn't the one with podman. The project is expected at
`D:\Git\WentTheFox\JellyfinDualboot`.

## Troubleshooting

- **Jellyfin stops by itself after exactly 10 minutes**: the media mount has `x-systemd.idle-timeout`.
  The container's bind mount doesn't count as autofs activity, so systemd unmounts the share and stops
  Jellyfin (it `Requires=` the mount). Don't use an idle timeout on the media mount (Linux fstab or WSL2).
- **`/media` is empty in the container**: the share wasn't mounted when the container started. Mount it
  first (on Linux the systemd unit requires `MEDIA_DIR`).
- **Volume mount fails with "run ./jf setup first"**: the VHDX has no filesystem yet.
- **Permission denied on `/config`**: files must be owned by uid 1000 on both sides.
- **GPU missing in the container**: regenerate `/etc/cdi/nvidia.yaml` after a driver update.
- **D: is read-only on Linux**: Windows left it dirty. Boot Windows, run `chkdsk D: /f`, and disable
  Fast Startup.
- **Volume attached but not mounted** (after a crash): check `lsblk`, then `sudo qemu-nbd -d /dev/nbd0`
  and start again.
