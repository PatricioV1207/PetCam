# AGENTS.md — PetCam

> PetCam is a Raspberry Pi 5 pet camera running Ubuntu 24.04 with a USB webcam.
> Phases 0–3 are implemented: live HLS stream, 12-hour recording retention,
> and a web UI with FastAPI backend. See `docs/` for full plan.

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

- `apps/api/` — FastAPI backend (health, recordings, static frontend)
- `infra/mediamtx.yml` — MediaMTX config (recording enabled, 10m segments, 12h retention)
- `scripts/` — `check_camera.sh` (validation), `start_camera.sh` (stream), `cleanup_recordings.sh` (safety retention)
- `systemd/` — service unit files and timer
- `data/recordings/` — runtime recordings (gitignored)

## Current State (Phases 0–3)

Goal phases reached:
- Phase 0/1: USB webcam → FFmpeg → MediaMTX → local browser live view
- Phase 2: Recording enabled with 12-hour retention
- Phase 3: Web UI + FastAPI backend for health, recordings, playback

What is implemented:
- Camera validation script
- MediaMTX with HLS enabled and recording active (10m segments, 12h auto-delete)
- FFmpeg stream pipeline (env-configurable)
- systemd services for MediaMTX, stream, API, and cleanup timer
- FastAPI backend (`apps/api/main.py`) with `/health`, `/api/recordings`, file serving
- Responsive web frontend with live HLS view, recording list, click-to-play

What is NOT implemented (future):
- Tailscale remote access (Phase 5)

## Constraints

- Ubuntu 24.04 only. CSI cameras unsupported; use USB webcam.
- No AI, motion detection, or notifications in current scope.
- `data/`, `.env*`, `*.log`, `node_modules/`, `.venv/`, `dist/`, `build/`, `__pycache__/` are gitignored.
- Do not add a framework or toolchain unless asked.
- `hlsAddress :8888` binds to all interfaces. OK for LAN. Not for public internet.
- Recording retention: 10m segments, 12h rolling window. Configured in `infra/mediamtx.yml`.

## Verification

From the Pi:
```bash
# Check camera
sudo -u petcam /opt/petcam/scripts/check_camera.sh

# Check stream
curl -s http://localhost:8888/cam/index.m3u8

# Check recordings
ls -lh /opt/petcam/data/recordings/cam/

# Check recording cleanup timer
sudo systemctl status petcam-cleanup.timer
sudo journalctl -u petcam-cleanup --since "1 hour ago"

# Check API
curl http://localhost:8000/health
curl http://localhost:8000/api/recordings

# Check service status
sudo systemctl status petcam-mediamtx petcam-stream petcam-api

# Open web UI
echo "http://<pi-ip>:8000"
```
