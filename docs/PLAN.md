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
│   ├── api/                    # Python + FastAPI (future)
│   └── web/                    # Web frontend (future)
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
│   └── cleanup_recordings.sh   # Safety retention cleanup (Phase 2)
├── systemd/
│   ├── petcam-mediamtx.service
│   ├── petcam-stream.service
│   ├── petcam-api.service       # Phase 3
│   └── petcam-cleanup.timer     # Phase 2
├── data/
│   └── recordings/             # Runtime recordings (gitignored)
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
- Set `recordSegmentDuration: 10m` (practical for testing; adjust to `1h` for production)
- Set `recordDeleteAfter: 12h`
- Add safety `cleanup_recordings.sh` + systemd timer (every 10 min)
- Verify recordings appear and old ones are cleaned

### Phase 3 — Web Frontend & API
- Python FastAPI backend: list recordings, serve static files
- Simple web page with HLS live view + recording playback
- systemd service for API

### Phase 4 — Autostart Hardening
- Review and enable all systemd services
- Test reboot → working stream

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
