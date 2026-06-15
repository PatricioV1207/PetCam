#!/bin/bash
set -euo pipefail

RECORDINGS_DIR="${RECORDINGS_DIR:-/opt/petcam/data/recordings}"
PLAYBACK_CACHE_DIR="${PLAYBACK_CACHE_DIR:-/opt/petcam/data/playback-cache}"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <relative_path>"
  echo "  relative_path: path relative to RECORDINGS_DIR (e.g. cam/2026-06-15_14-27-32-492274.mp4)"
  exit 1
fi

RELATIVE_PATH="$1"

# Resolve input path and guard against traversal
INPUT="$(cd "$RECORDINGS_DIR" && readlink -f -- "$RELATIVE_PATH" 2>/dev/null)" || {
  echo "ERROR: could not resolve path: $RELATIVE_PATH"
  exit 1
}

if ! case "$INPUT" in "$RECORDINGS_DIR"/*) true;; *) false;; esac; then
  echo "ERROR: path traversal detected: $INPUT"
  exit 1
fi

if [ ! -f "$INPUT" ]; then
  echo "ERROR: file not found: $INPUT"
  exit 1
fi

# Build output path under playback-cache, preserving subdirectories
CACHE_FILE="$PLAYBACK_CACHE_DIR/$RELATIVE_PATH"
CACHE_DIR="$(dirname "$CACHE_FILE")"
mkdir -p "$CACHE_DIR"

# Only remux if the cache does not exist or the source is newer
if [ -f "$CACHE_FILE" ] && [ "$INPUT" -nt "$CACHE_FILE" ]; then
  rm -f "$CACHE_FILE"
fi

if [ ! -f "$CACHE_FILE" ]; then
  echo "Remuxing $RELATIVE_PATH -> $CACHE_FILE"
  ffmpeg -y -i "$INPUT" -c copy -movflags +faststart "$CACHE_FILE"
else
  echo "Using cached: $CACHE_FILE"
fi

echo "$CACHE_FILE"
