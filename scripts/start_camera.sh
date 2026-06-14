#!/bin/bash
set -euo pipefail

DEVICE="${DEVICE:-/dev/video0}"
INPUT_FORMAT="${INPUT_FORMAT:-mjpeg}"
RESOLUTION="${RESOLUTION:-1280x720}"
FRAMERATE="${FRAMERATE:-30}"
BITRATE="${BITRATE:-2M}"
PRESET="${PRESET:-veryfast}"
MEDIAMTX_HOST="${MEDIAMTX_HOST:-localhost}"
MEDIAMTX_PORT="${MEDIAMTX_PORT:-8554}"
STREAM_PATH="${STREAM_PATH:-cam}"

# GOP = 2 seconds of frames
GOP=$((FRAMERATE * 2))

echo "Starting PetCam stream:"
echo "  Device:       $DEVICE"
echo "  Input format: $INPUT_FORMAT"
echo "  Resolution:   $RESOLUTION"
echo "  Framerate:    $FRAMERATE"
echo "  Bitrate:      $BITRATE"
echo "  Target:       rtsp://$MEDIAMTX_HOST:$MEDIAMTX_PORT/$STREAM_PATH"

exec ffmpeg \
  -f v4l2 \
  -input_format "$INPUT_FORMAT" \
  -video_size "$RESOLUTION" \
  -framerate "$FRAMERATE" \
  -thread_queue_size 512 \
  -i "$DEVICE" \
  -c:v libx264 \
  -pix_fmt yuv420p \
  -preset "$PRESET" \
  -b:v "$BITRATE" \
  -maxrate "$BITRATE" \
  -bufsize "$BITRATE" \
  -g "$GOP" \
  -keyint_min "$GOP" \
  -sc_threshold 0 \
  -f rtsp \
  -rtsp_transport tcp \
  "rtsp://$MEDIAMTX_HOST:$MEDIAMTX_PORT/$STREAM_PATH"
