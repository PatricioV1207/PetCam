# PetCam — Raspberry Pi 5 Setup Guide

## Prerequisites

- Raspberry Pi 5
- Ubuntu 24.04 LTS installed (Server or Desktop)
- USB webcam (UVC-compatible)
- 128 GB microSD card (or larger)
- Network access (Ethernet or Wi-Fi)
- SSH access (recommended)

---

## 1. Prepare Ubuntu 24.04

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install essential tools
sudo apt install -y v4l-utils ffmpeg curl

# Set hostname (replace with your desired name)
sudo hostnamectl set-hostname petcam
```

---

## 2. Create `petcam` User and Directories

```bash
# Create system user for PetCam services
sudo useradd -r -s /bin/false -m -d /opt/petcam petcam

# Add petcam to the video group (required for /dev/video0 access)
sudo usermod -a -G video petcam

# Create runtime directories
sudo mkdir -p /opt/petcam/data/recordings
sudo mkdir -p /opt/petcam/logs

# Set ownership
sudo chown -R petcam:petcam /opt/petcam
```

---

## 3. Install MediaMTX

PetCam uses the native MediaMTX binary (not Docker).

```bash
cd /tmp

# Find the latest release version at https://github.com/bluenviron/mediamtx/releases
wget https://github.com/bluenviron/mediamtx/releases/download/v1.19.1/mediamtx_v1.19.1_linux_arm64.tar.gz

tar xzf mediamtx_v1.19.1_linux_arm64.tar.gz

# Install to system path
sudo mv mediamtx /usr/local/bin/
sudo chmod +x /usr/local/bin/mediamtx

# Verify
mediamtx --version
```

---

## 4. Deploy PetCam Files

Copy the repository contents to `/opt/petcam`. From the repository root:

```bash
# If cloning from git:
# git clone <repo-url> /opt/petcam

# Make all scripts executable
chmod +x /opt/petcam/scripts/*.sh

# Create the .env file from the example
cp /opt/petcam/.env.example /opt/petcam/.env
```

---

## 5. Configure Environment

Edit `/opt/petcam/.env`:

```bash
DEVICE=/dev/video0

# Check supported formats with:
#   v4l2-ctl -d /dev/video0 --list-formats-ext
# Use mjpeg if available (lower CPU). Fall back to yuyv422 if needed.
INPUT_FORMAT=mjpeg

# MVP settings: 720p30 at 2 Mbps for stability
RESOLUTION=1280x720
FRAMERATE=30
BITRATE=2M
PRESET=veryfast

MEDIAMTX_HOST=localhost
MEDIAMTX_PORT=8554
STREAM_PATH=cam
```

---

## 6. Validate Camera

Plug in the USB webcam and run:

```bash
# Add your user to video group if not already
sudo usermod -a -G video $USER
newgrp video  # apply group changes in current shell

# Run the camera check
sudo -u petcam /opt/petcam/scripts/check_camera.sh
```

Expected output:
- `/dev/video0` is found
- Supported formats are listed
- A 10-second test clip is saved to `/tmp/petcam_test.mp4`

If the test clip fails or the wrong format is detected, edit `INPUT_FORMAT` in `/opt/petcam/.env` and re-run.

---

## 7. Test Live Stream (Manual)

```bash
# Start MediaMTX in background
sudo -u petcam /usr/local/bin/mediamtx /opt/petcam/infra/mediamtx.yml &
# Wait a moment, then:

# Start the camera stream
sudo -u petcam /opt/petcam/scripts/start_camera.sh
```

In another terminal window (or from another machine on the same network), verify:

```bash
# Check that RTSP is receiving
ffplay rtsp://<pi-ip>:8554/cam

# Check HLS is being served
curl -I http://<pi-ip>:8888/cam/index.m3u8
```

Open a browser at `http://<pi-ip>:8888/cam` to view the live stream.

> Note: `hlsAddress :8888` binds to all network interfaces. This is acceptable for LAN testing. Do NOT expose this port to the public internet. Remote access is handled via Tailscale in Phase 5.

---

## 8. Enable Autostart Services

```bash
# Copy service files
sudo cp /opt/petcam/systemd/petcam-mediamtx.service /etc/systemd/system/
sudo cp /opt/petcam/systemd/petcam-stream.service /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable and start services
sudo systemctl enable --now petcam-mediamtx.service
sudo systemctl enable --now petcam-stream.service

# Check status
sudo systemctl status petcam-mediamtx.service
sudo systemctl status petcam-stream.service

# View logs
sudo journalctl -u petcam-mediamtx -f
sudo journalctl -u petcam-stream -f
```

---

## 9. Verify After Reboot

```bash
sudo reboot
# After Pi comes back:
sudo systemctl status petcam-mediamtx
sudo systemctl status petcam-stream
# Open browser to http://<pi-ip>:8888/cam
```

---

## 10. Enable Recording (Phase 2)

Recording is now active. MediaMTX will write 10-minute fMP4 segments to `/opt/petcam/data/recordings/cam/` and automatically delete segments older than 12 hours.

```bash
# Update MediaMTX config (record: true, segment: 10m, retention: 12h)
# The config file /opt/petcam/infra/mediamtx.yml was already deployed.

# Restart MediaMTX to pick up the new config
sudo systemctl restart petcam-mediamtx

# Verify recordings are being created
watch -n 5 'ls -lh /opt/petcam/data/recordings/cam/'

# After a few minutes, you should see .mp4 files appearing
```

### Safety Cleanup Service

A secondary cleanup script runs every 10 minutes via systemd timer:

```bash
# Copy the cleanup service and timer
sudo cp /opt/petcam/systemd/petcam-cleanup.service /etc/systemd/system/
sudo cp /opt/petcam/systemd/petcam-cleanup.timer /etc/systemd/system/

# Reload and enable
sudo systemctl daemon-reload
sudo systemctl enable --now petcam-cleanup.timer

# Verify the timer is active
sudo systemctl status petcam-cleanup.timer
systemctl list-timers --all | grep petcam
```

### Verify Recording

```bash
# List recordings
ls -lh /opt/petcam/data/recordings/cam/

# Check that the cleanup timer ran
sudo journalctl -u petcam-cleanup --since "5 minutes ago"

# Safely test cleanup (dry run — find what would be deleted):
sudo -u petcam find /opt/petcam/data/recordings -type f -mmin +700 -ls
```

### Adjusting Segment Duration

Edit `recordSegmentDuration` in `infra/mediamtx.yml`. For production use, change `10m` to `1h` to reduce file count:

```yaml
recordSegmentDuration: 1h
```

Then restart MediaMTX:
```bash
sudo systemctl restart petcam-mediamtx
```

---

## 11. Web UI + API (Phase 3)

### 11.1 Create Python Virtual Environment

```bash
sudo -u petcam python3 -m venv /opt/petcam/.venv
sudo -u petcam /opt/petcam/.venv/bin/pip install -r /opt/petcam/apps/api/requirements.txt
```

### 11.2 Update .env with API Variables

Add to `/opt/petcam/.env`:

```bash
API_HOST=0.0.0.0
API_PORT=8000
RECORDINGS_DIR=/opt/petcam/data/recordings
LIVE_HLS_URL=http://localhost:8888/cam/index.m3u8
```

### 11.3 Start the API Service

```bash
sudo cp /opt/petcam/systemd/petcam-api.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now petcam-api.service

# Check it's running
sudo systemctl status petcam-api.service
sudo journalctl -u petcam-api.service -n 30
```

### 11.4 Test the API

```bash
# Health check
curl http://localhost:8000/health

# Recordings list (should show files when recordings exist)
curl http://localhost:8000/api/recordings

# Open in browser
echo "http://<pi-ip>:8000"
```

### 11.5 Access the Web UI

Open a browser from any device on the same LAN:

```
http://<pi-ip>:8000
```

The page shows:
- Live camera stream via hls.js
- Recordings list (click to play)
- Storage usage footer

### 11.6 (Optional) Download hls.js Locally

The frontend loads hls.js from a CDN by default. To vendor it locally on the Pi:

```bash
curl -L -o /opt/petcam/apps/api/static/vendor/hls.min.js \
  https://cdn.jsdelivr.net/npm/hls.js@latest/dist/hls.min.js
```

Then update `index.html` to use `/vendor/hls.min.js` instead of the CDN URL.

---

## 12. Tailscale (Future — Phase 5)

Tailscale remote access is not set up yet. After local streaming works, Phase 5 will cover:

1. Creating a Tailscale account at https://tailscale.com
2. Installing Tailscale on the Pi
3. Authenticating to the tailnet
4. Using `tailscale serve` to expose the web UI via HTTPS

---

## Troubleshooting

### Camera not found
```bash
# Check USB devices
lsusb

# Check V4L2 devices
v4l2-ctl --list-devices

# Check kernel messages
dmesg | grep video
```

### Permission denied on /dev/video0
```bash
# Ensure user is in video group
groups petcam
sudo usermod -a -G video petcam
```

### No HLS stream in browser
```bash
# Check MediaMTX is running
sudo systemctl status petcam-mediamtx

# Check stream is publishing
curl -s http://localhost:8888/cam/index.m3u8

# Check FFmpeg logs
sudo journalctl -u petcam-stream -n 50
```

### CPU too high
- Lower resolution in `.env`: `RESOLUTION=640x480`
- Lower framerate: `FRAMERATE=15`
- Use `mjpeg` input format instead of `yuyv422`
