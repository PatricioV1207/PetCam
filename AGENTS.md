# AGENTS.md — PetCam

> PetCam is a Raspberry Pi 5 pet camera running Ubuntu 24.04 with a USB webcam.
> Currently implementing Phase 0 (hardware validation) and Phase 1 (live HLS stream).
> No backend API, web frontend, or recording enabled yet. See `docs/` for full plan.

## Quick Facts

- **Camera**: USB UVC webcam on `/dev/video0`. Not Raspberry Pi CSI camera (libcamera/PiSP not supported on Ubuntu 24.04).
- **Streamer**: MediaMTX native ARM64 binary (not Docker). Configuration at `infra/mediamtx.yml`.
- **Capture**: FFmpeg V4L2 → H.264 → RTSP → MediaMTX. Script at `scripts/start_camera.sh`.
- **Playback**: HLS on port `8888`. View at `http://<pi-ip>:8888/cam`.
- **Resolution**: 720p30 at 2 Mbps for MVP. Configurable via `.env`.
- **Input format**: Configurable (`INPUT_FORMAT`), defaults to `mjpeg`. Change to `yuyv422` if camera doesn't support MJPEG.
- **Autostart**: Native systemd services (not Docker). Service files in `systemd/`.
- **Remote access**: Tailscale Serve (not yet configured — Phase 5).

## Directory Layout

- `apps/api/`, `apps/web/` — to be implemented in Phase 3
- `infra/mediamtx.yml` — MediaMTX config (recording disabled in Phase 1)
- `scripts/` — `check_camera.sh` (validation), `start_camera.sh` (stream)
- `systemd/` — service unit files
- `data/recordings/` — runtime recordings (gitignored)

## Current State (Phases 0 & 1)

Goal: USB webcam → FFmpeg → MediaMTX → local browser live view.

What is implemented:
- Camera validation script
- MediaMTX with HLS enabled, recording disabled
- FFmpeg stream pipeline (env-configurable)
- systemd service templates for MediaMTX and stream

What is NOT implemented (future):
- Recording (Phase 2)
- Python FastAPI backend (Phase 3)
- Web frontend (Phase 3)
- Tailscale remote access (Phase 5)

## Verification

From the Pi:
```bash
# Check camera
sudo -u petcam /opt/petcam/scripts/check_camera.sh

# Check stream
curl -s http://localhost:8888/cam/index.m3u8

# Check status
sudo systemctl status petcam-mediamtx petcam-stream
```

## Constraints

- Ubuntu 24.04 only. CSI cameras unsupported; use USB webcam.
- No AI, motion detection, or notifications in current scope.
- `data/`, `.env*`, `*.log`, `node_modules/`, `.venv/`, `dist/`, `build/`, `__pycache__/` are gitignored.
- Do not add a framework or toolchain unless asked.
- `hlsAddress :8888` binds to all interfaces. OK for LAN. Not for public internet.
