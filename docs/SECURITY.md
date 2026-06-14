# PetCam — Security Model

## Principles

1. **No public internet exposure.** All services bind to localhost or the local LAN. Remote access is achieved only through Tailscale, which establishes an encrypted peer-to-peer connection.
2. **Least privilege.** Services run as the `petcam` user, not root. File permissions restrict access to the `petcam` user only.
3. **No secrets in Git.** Configuration values are stored in `/opt/petcam/.env`, which is not tracked by Git.

---

## Network Exposure

| Port | Service | Bind | Acceptable For |
|---|---|---|---|---|
| `8554` | MediaMTX RTSP | `:8554` (all interfaces) | LAN only |
| `8888` | MediaMTX HLS | `:8888` (all interfaces) | LAN only |
| `1935` | MediaMTX RTMP | `:1935` (all interfaces) | LAN only |
| `8000` | FastAPI backend | `0.0.0.0:8000` | LAN only |

> **WARNING:** These ports are bound to all network interfaces. On a home network behind a NAT router this is acceptable for LAN testing. However, these ports **must not be forwarded** on your router or exposed to the public internet. Remote access is handled exclusively via Tailscale (Phase 5).

## API Path Traversal Prevention

The `/api/recordings/file/{path}` endpoint resolves requested paths against `RECORDINGS_DIR` and rejects any path that escapes the recordings directory. Only files under `/opt/petcam/data/recordings` are accessible.

## Tailscale (Phase 5)

- Create a Tailscale account at https://tailscale.com
- Install Tailscale on the Pi and authenticate to your tailnet
- Use `tailscale serve` to expose the web UI/API as HTTPS on the tailnet
- Tailscale manages encryption and authentication; no certificates to handle manually
- Optionally restrict access using Tailscale ACLs

## Service User

- All PetCam services run as the `petcam` system user
- The `petcam` user has no login shell (`/bin/false`)
- The `petcam` user is in the `video` group for camera access
- Home directory is `/opt/petcam`

## File Permissions

```
/opt/petcam/                     petcam:petcam  755
/opt/petcam/data/recordings/     petcam:petcam  750
/opt/petcam/.env                 petcam:petcam  600
/opt/petcam/scripts/*.sh         petcam:petcam  755
```

## Secrets

- No API keys, passwords, or tokens are stored in Git
- Camera configuration is in `/opt/petcam/.env` (gitignored)
- `.env.example` is provided as a template with no real secrets

## SSH

- Use key-based authentication only
- Disable password SSH login if the Pi is reachable from untrusted networks

## Updates

Keep the system and components updated:

```bash
sudo apt update && sudo apt upgrade -y    # system + ffmpeg
# MediaMTX: download latest binary from GitHub releases
# Tailscale: updates automatically
```

## Future Considerations

- Basic HTTP authentication on the web UI/FastAPI (before Tailscale is set up)
- Tailscale ACLs to restrict which devices can reach the Pi
- Read-only API for external clients
- Disk-full detection to prevent failures
- Recording retention is enforced by both MediaMTX (`recordDeleteAfter: 12h`) and an independent systemd cleanup timer — recordings older than 12 hours are deleted on schedule
