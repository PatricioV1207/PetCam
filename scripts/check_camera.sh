#!/bin/bash
set -euo pipefail

DEVICE="${DEVICE:-/dev/video0}"
INPUT_FORMAT="${INPUT_FORMAT:-mjpeg}"
RESOLUTION="${RESOLUTION:-1280x720}"
FRAMERATE="${FRAMERATE:-30}"

echo "=== PetCam Camera Check ==="

echo ""
echo "Detecting V4L2 devices..."
v4l2-ctl --list-devices || true

echo ""
if [ ! -e "$DEVICE" ]; then
  echo "ERROR: $DEVICE not found."
  echo "Make sure the USB webcam is plugged in and recognized by the system."
  exit 1
fi
echo "Found $DEVICE"

echo ""
echo "Supported formats for $DEVICE:"
v4l2-ctl -d "$DEVICE" --list-formats-ext

echo ""
echo "Capturing 10-second test clip to /tmp/petcam_test.mp4..."
echo "Using input format: $INPUT_FORMAT"

ffmpeg -y -f v4l2 \
  -input_format "$INPUT_FORMAT" \
  -video_size "$RESOLUTION" \
  -framerate "$FRAMERATE" \
  -i "$DEVICE" \
  -c:v libx264 \
  -preset veryfast \
  -pix_fmt yuv420p \
  -t 10 \
  /tmp/petcam_test.mp4

echo ""
echo "Test clip saved to /tmp/petcam_test.mp4"
echo "Camera check passed."
