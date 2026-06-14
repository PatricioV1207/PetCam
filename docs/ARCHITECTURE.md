# PetCam — Architecture

## Overview

PetCam captures video from a USB webcam on a Raspberry Pi 5, streams it through MediaMTX, and serves a live HLS view to browsers on the local network. Remote access is provided via Tailscale. Recordings are stored locally with a 12-hour rolling window.

## Data Flow (Phase 1)

```
┌──────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  USB Webcam  │────▶│  FFmpeg (V4L2)   │────▶│    MediaMTX       │
│  /dev/video0 │     │  H.264 encode    │     │  (RTSP → HLS)    │
│              │     │  RTSP publish    │     │  port 8554/8888  │
└──────────────┘     └──────────────────┘     └────────┬─────────┘
                                                        │
                                              ┌─────────▼─────────┐
                                              │    Browser (HLS)   │
                                              │  http://pi:8888/cam│
                                              └───────────────────┘
```

## Data Flow (Phase 2+)

```
┌──────────────┐     ┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  USB Webcam  │────▶│  FFmpeg (V4L2)   │────▶│    MediaMTX       │────▶│     Browser      │
│  /dev/video0 │     │  H.264 encode    │     │  RTSP → HLS +    │     │  (live + replay) │
│              │     │  RTSP publish    │     │  Record to disk  │     │                  │
└──────────────┘     └──────────────────┘     └────────┬─────────┘     └──────────────────┘
                                                        │
                                                        ▼
                                              ┌──────────────────┐
                                              │   Recordings on  │
                                              │   microSD (12h)  │
                                              │   /data/recordings│
                                              └──────────────────┘
```

## System Components

### FFmpeg (capture pipeline)
- Reads from `/dev/video0` via V4L2
- Uses `INPUT_FORMAT` (default `mjpeg`) from config
- Encodes to H.264 software (`libx264`)
- Publishes via RTSP (`rtsp://localhost:8554/cam`)

### MediaMTX (streaming server)
- Native ARM64 binary, not Docker
- Receives RTSP stream from FFmpeg
- Transmuxes to HLS on port `8888`
- Phase 2: also records segments to disk

### Python FastAPI (future — Phase 3)
- Lists recordings from filesystem
- Serves static web frontend
- Provides health/status endpoint

### systemd services
- `petcam-mediamtx.service` — starts MediaMTX after network
- `petcam-stream.service` — starts FFmpeg capture after MediaMTX
- `petcam-api.service` (Phase 3) — starts FastAPI
- `petcam-cleanup.timer` (Phase 2) — periodic retention cleanup

### Web Frontend (future — Phase 3)
- Vanilla HTML/JS with hls.js
- Live stream from HLS endpoint
- List and play recordings

### Tailscale (Phase 5)
- Remote access via `tailscale serve`
- HTTPS via Tailscale certificates
- No public port exposure

## Directory Ownership

```
/opt/petcam/                       petcam:petcam
/opt/petcam/data/recordings/       petcam:petcam  (mode 750)
```

All services run as the `petcam` user.

## Recording Architecture (Phase 2)

- MediaMTX segments: 10-minute `.mp4` files (`recordSegmentDuration: 10m`)
- Retention: `recordDeleteAfter: 12h` in MediaMTX (primary enforcement)
- Safety net: `cleanup_recordings.sh` via systemd timer (every 10 min)
  - Deletes files older than 720 minutes (12 hours)
  - Removes empty directories
  - Guards against empty or invalid paths
- Two independent mechanisms ensure retention is reliable
