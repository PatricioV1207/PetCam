# AGENTS.md — PetCam

> PetCam is a Raspberry Pi 5 pet camera running Ubuntu 24.04 with a USB webcam.
> Phases 0–4 are implemented: live HLS stream, 12-hour recording retention,
> web UI with FastAPI backend, and hardened systemd autostart with diagnostics.

## Quick Facts

- **Camera**: USB UVC webcam on `/dev/video0`. Not Raspberry Pi CSI camera (libcamera/PiSP not supported on Ubuntu 24.04).
- **Streamer**: MediaMTX native ARM64 binary (not Docker). Configuration at `infra/mediamtx.yml`.
- **Capture**: FFmpeg V4L2 → H.264 → RTSP → MediaMTX. Script at `scripts/start_camera.sh`.
- **Playback**: HLS on port `8888`. View at `http://<pi-ip>:8888/cam`.
- **Resolution**: 720p20 at 1 Mbps for MVP. Configurable via `.env`.
- **Input format**: Configurable (`INPUT_FORMAT`), defaults to `mjpeg`. Change to `yuyv422` if camera doesn't support MJPEG.
- **Autostart**: Native systemd services (not Docker). Service files in `systemd/`.
- **Remote access**: Tailscale Serve (not yet configured — Phase 5).

## Directory Layout

- `apps/api/` — FastAPI backend (health, recordings, static frontend)
- `infra/mediamtx.yml` — MediaMTX config (recording enabled, 5m segments, 12h retention)
- `scripts/` — `check_camera.sh` (validation), `start_camera.sh` (stream), `cleanup_recordings.sh` (safety retention), `remux_recording.sh` (browser playback), `status.sh` (status), `reboot_test_check.sh` (reboot verification), `diagnose.sh` (diagnostics)
- `systemd/` — hardened service unit files and timer
- `data/recordings/` — runtime recordings (gitignored)
- `data/playback-cache/` — remuxed MP4s for browser (gitignored)

## Current State (Phases 0–4)

Goal phases reached:
- Phase 0/1: USB webcam → FFmpeg → MediaMTX → local browser live view
- Phase 2: Recording enabled with 12-hour retention
- Phase 3: Web UI + FastAPI backend for health, recordings, playback
- Phase 4: Hardened systemd services with restart backoff, diagnostics scripts

What is implemented:
- Camera validation script
- MediaMTX with HLS enabled and recording active (5m segments, 12h auto-delete)
- FFmpeg stream pipeline (env-configurable)
- systemd services for MediaMTX, stream, API, and cleanup timer
- FastAPI backend (`apps/api/main.py`) with `/health`, `/api/recordings`, `/api/recordings/playable/{path}` (remux), file serving
- Responsive web frontend with live HLS view, recording list, click-to-play, download original
- systemd hardening: restart backoff, PrivateTmp, NoNewPrivileges, device access controls
- Diagnostic scripts: `status.sh`, `reboot_test_check.sh`, `diagnose.sh`

What is NOT implemented (future):
- Tailscale remote access (Phase 5)

## Constraints

- Ubuntu 24.04 only. CSI cameras unsupported; use USB webcam.
- No AI, motion detection, or notifications in current scope.
- `data/`, `.env*`, `*.log`, `node_modules/`, `.venv/`, `dist/`, `build/`, `__pycache__/` are gitignored.
- Do not add a framework or toolchain unless asked.
- `hlsAddress :8888` binds to all interfaces. OK for LAN. Not for public internet.
- Recording retention: 5m segments, 12h rolling window. Configured in `infra/mediamtx.yml`.
- Playback remux cache (`data/playback-cache/`) also cleaned after 12h.

## Constraints

- Ubuntu 24.04 only. CSI cameras unsupported; use USB webcam.
- No AI, motion detection, or notifications in current scope.
- `data/`, `.env*`, `*.log`, `node_modules/`, `.venv/`, `dist/`, `build/`, `__pycache__/` are gitignored.
- Do not add a framework or toolchain unless asked.
- `hlsAddress :8888` binds to all interfaces. OK for LAN. Not for public internet.
- Recording retention: 5m segments, 12h rolling window. Configured in `infra/mediamtx.yml`.
- Playback remux cache (`data/playback-cache/`) also cleaned after 12h.
- `PrivateDevices=yes` and `ProtectSystem=strict` are NOT used — they break camera access and file writes.

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

# Test playable endpoint (substitute a real recording path)
curl -I "http://localhost:8000/api/recordings/playable/cam/2026-06-15_14-27-32-492274.mp4"

# Check service status
sudo systemctl status petcam-mediamtx petcam-stream petcam-api petcam-cleanup.timer

# Run status script
sudo -u petcam /opt/petcam/scripts/status.sh

# Run diagnostics
sudo -u petcam /opt/petcam/scripts/diagnose.sh

# Open web UI
echo "http://<pi-ip>:8000"
```
