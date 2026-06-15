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

## Data Flow (Phase 3)

```
┌──────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  USB Webcam  │────▶│  FFmpeg (V4L2)   │────▶│    MediaMTX       │
│  /dev/video0 │     │  H.264 encode    │     │  RTSP → HLS +    │
│              │     │  RTSP publish    │     │  Record to disk  │
└──────────────┘     └──────────────────┘     └────────┬─────────┘
                                                        │
                                                        ├──────────────────────┐
                                                        ▼                      ▼
                                              ┌──────────────────┐   ┌──────────────────┐
                                              │  FastAPI (8000)  │   │ Recordings on    │
                                              │  / → index.html  │   │ microSD (12h)    │
                                              │  /health         │   │ /data/recordings │
                                              │  /api/recordings │   └──────────────────┘
                                              │  /api/recordings │
                                              │   /file/{path}  │
                                              └────────┬─────────┘
                                                       │
                                              ┌─────────▼─────────┐
                                              │  Browser (hls.js) │
                                              │  Live + Playback  │
                                              │  http://pi:8000   │
                                              └───────────────────┘
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

### Python FastAPI (Phase 3)
- Endpoints:
  - `GET /health` — service status, storage usage
  - `GET /api/recordings` — JSON list of recording files (newest first)
  - `GET /api/recordings/file/{path}` — serve raw recording file (path-traversal safe)
  - `GET /api/recordings/playable/{path}` — serve browser-friendly MP4 (remux with `-movflags +faststart`, cache in `playback-cache/`)
  - `GET /` — serve static frontend
- Binds to `0.0.0.0:8000` for LAN access

### systemd services
- `petcam-mediamtx.service` — starts MediaMTX after network
- `petcam-stream.service` — starts FFmpeg capture after MediaMTX
- `petcam-api.service` — starts FastAPI on port 8000
- `petcam-cleanup.service` + `.timer` — periodic retention cleanup

### Web Frontend (Phase 3)
- Vanilla HTML/CSS/JS single-page app
- Live stream via hls.js from MediaMTX HLS endpoint
- Recordings list with refresh, file size, modified time
- Click-to-play in HTML5 video player
- Responsive design (works on phone)
- hls.js loaded from CDN (can be vendored locally)

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

## Recording Architecture

- MediaMTX segments: 5-minute `.mp4` files (`recordSegmentDuration: 5m`)
- Retention: `recordDeleteAfter: 12h` in MediaMTX (primary enforcement)
- Safety net: `cleanup_recordings.sh` via systemd timer (every 10 min)
  - Deletes recording files older than 720 minutes (12 hours)
  - Also cleans `playback-cache/` directory with the same retention
  - Removes empty directories
  - Guards against empty or invalid paths
- Two independent mechanisms ensure retention is reliable

## Playback Remuxing

- MediaMTX records in fMP4 format (fragmented MP4). The moov atom is at the end of the file, which can cause browser loading issues.
- `GET /api/recordings/playable/{path}` remuxes the file without re-encoding: `ffmpeg -c copy -movflags +faststart`
- Remuxed files are stored in `data/playback-cache/` (gitignored)
- The cache preserves the same directory structure as recordings
- Cache invalidation: if the source recording is newer than the cached file, it is re-remuxed on next request
- A remuxed 5-minute segment at 1 Mbps ≈ 37 MB
