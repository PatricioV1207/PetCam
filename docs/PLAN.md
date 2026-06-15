# PetCam — Implementation Plan

## Goal

Private pet surveillance camera for dogs. Runs on a Raspberry Pi 5 with Ubuntu 24.04. Uses a USB webcam, MediaMTX for streaming, FFmpeg for capture, and locally-stored recordings with a 12-hour rolling retention window. Remote access via Tailscale.

## Constraints

- Target device: Raspberry Pi 5
- OS: Ubuntu 24.04 LTS
- Camera: USB UVC webcam (not Raspberry Pi CSI camera — libcamera/PiSP not supported on Ubuntu 24.04)
- Storage: 128 GB microSD card
- No AI, motion detection, notifications, or complex dashboard in the MVP

## Technology Decisions

| Concern | Choice |
|---|---|
| Streaming server | MediaMTX native ARM64 binary |
| Video capture | FFmpeg via V4L2 (`/dev/video0`) |
| Playback protocol | HLS (hls.js in browser) |
| Backend API | Python + FastAPI (introduced in Phase 3) |
| Autostart | systemd services |
| Remote access | Tailscale Serve (introduced in Phase 5) |
| Recording retention | MediaMTX `recordDeleteAfter: 12h` + safety cleanup script |
| Containers | Not used in MVP; MediaMTX runs as native binary |

## Project Structure

```
petcam/
├── apps/
│   ├── api/                    # FastAPI backend (Phase 3: health, recordings, playback, static frontend)
│   └── web/                    # reserved for future use
├── docs/
│   ├── PLAN.md
│   ├── ARCHITECTURE.md
│   ├── SETUP_RPI.md
│   └── SECURITY.md
├── infra/
│   ├── mediamtx.yml            # MediaMTX configuration
│   └── docker-compose.yml      # optional, not used in MVP
├── scripts/
│   ├── check_camera.sh         # Validate camera and test capture
│   ├── start_camera.sh         # Publish camera to MediaMTX
│   ├── cleanup_recordings.sh   # Safety retention cleanup (Phase 2)
│   ├── remux_recording.sh      # Remux recording for browser playback (Phase 3.5)
│   ├── status.sh               # One-glance status summary (Phase 4)
│   ├── reboot_test_check.sh    # Post-reboot verification (Phase 4)
│   └── diagnose.sh             # Diagnostic info collection (Phase 4)
├── systemd/
│   ├── petcam-mediamtx.service  # Hardened + restart backoff (Phase 4)
│   ├── petcam-stream.service    # Hardened + camera device access (Phase 4)
│   ├── petcam-api.service       # FastAPI backend, starts after stream (Phase 4)
│   ├── petcam-cleanup.service   # Hardened, startup-ordered (Phase 4)
│   └── petcam-cleanup.timer     # Safety retention cleanup (Phase 2)
├── data/
│   ├── recordings/             # Runtime recordings (gitignored)
│   └── playback-cache/         # Remuxed MP4s for browser (gitignored)
├── .env.example
└── AGENTS.md
```

## Phases

### Phase 0 — Hardware Validation & OS Preparation
- Install Ubuntu 24.04 on Raspberry Pi 5
- Install system packages: `v4l-utils`, `ffmpeg`, `curl`
- Create `petcam` user and `/opt/petcam` directory structure
- Add user to `video` group for camera access
- Install MediaMTX ARM64 binary
- Run `check_camera.sh` to validate USB webcam

### Phase 1 — Live Stream (current goal)
- Configure `infra/mediamtx.yml` (recording disabled)
- Publish camera to MediaMTX via `start_camera.sh`
- Verify live HLS stream in browser at `http://<pi-ip>:8888/cam`
- Create systemd services for autostart
- **Success criteria:** USB webcam detected → FFmpeg captures → MediaMTX receives → browser plays live

### Phase 2 — Recording & Retention
- Enable MediaMTX recording (`record: true`)
- Set `recordSegmentDuration: 5m` (practical for testing and playback; adjust to `1h` for production)
- Set `recordDeleteAfter: 12h`
- Add safety `cleanup_recordings.sh` + systemd timer (every 10 min)
- Verify recordings appear and old ones are cleaned

### Phase 3 — Web Frontend & API
- Python FastAPI backend: health, recordings list, file serving, static frontend
- Minimal HTML/CSS/JS frontend with hls.js live view + recording list + playback
- systemd service for API (`petcam-api.service`)
- API on port `8000`, accessible at `http://<pi-ip>:8000`

### Phase 3.5 — Browser Recording Playback Fix
- MediaMTX fMP4 recordings are not directly playable in browsers (moov atom at end)
- Add `scripts/remux_recording.sh`: `ffmpeg -c copy -movflags +faststart` (no re-encode)
- FastAPI endpoint `GET /api/recordings/playable/{path}` remuxes on first request and caches result
- Playback cache at `data/playback-cache/` — cleaned by same cleanup timer (12h retention)
- Frontend uses playable URL; "Download original" link remains for raw file
- Storage estimates: 1 Mbps ≈ 450 MB/hour, 800 kbps ≈ 360 MB/hour

### Phase 4 — Autostart Hardening & Diagnostics
- Add restart backoff to all services: `RestartSteps=5`, `RestartMaxDelaySec=60`, `StartLimitBurst=3`
- Apply systemd hardening: `PrivateTmp`, `NoNewPrivileges`, `ProtectHome`, `ProtectKernelTunables`,
  `ProtectKernelModules`, `ProtectControlGroups`, `RestrictSUIDSGID`, `RemoveIPC`, `RestrictRealtime`
- Stream service: add `SupplementaryGroups=video`, `DeviceAllow=/dev/video0 rw`, `/dev/video1 rw`
- API service: add `After=petcam-stream.service` (starts after stream is up)
- Cleanup service: add `After=` all petcam services to avoid startup races
- Create `scripts/status.sh` — one-glance status of all services, endpoints, storage
- Create `scripts/reboot_test_check.sh` — automated post-reboot verification with polling
- Create `scripts/diagnose.sh` — collect logs, camera info, disk usage
- **Do not** use `PrivateDevices=yes` or `ProtectSystem=strict` (breaks camera or recordings)
- **Success criteria:** After cold reboot, `reboot_test_check.sh` reports all PASS, `status.sh` shows all services active

### Phase 5 — Remote Access
- Install and authenticate Tailscale
- Expose web UI via `tailscale serve`
- Test from phone/laptop off-network

## Out of Scope (MVP)

- AI / object detection (no Frigate, no TensorFlow, no YOLO)
- Motion detection
- Push notifications
- Complex dashboard or user accounts
- Frigate integration
- Docker containers
