#!/bin/bash
set -euo pipefail

RECORDINGS_DIR="${RECORDINGS_DIR:-/opt/petcam/data/recordings}"
PLAYBACK_CACHE_DIR="${PLAYBACK_CACHE_DIR:-/opt/petcam/data/playback-cache}"
RETENTION_MINUTES="${RETENTION_MINUTES:-720}"

guard_directory() {
  local dir="$1"
  if [ -z "$dir" ] || [ ! -d "$dir" ]; then
    echo "ERROR: directory is empty or does not exist: $dir"
    return 1
  fi
  if [ "$dir" = "/" ] || [ "$dir" = "/home" ] || [ "$dir" = "/opt" ]; then
    echo "ERROR: refusing to clean system directory: $dir"
    return 1
  fi
  return 0
}

clean_directory() {
  local label="$1"
  local dir="$2"
  echo ""
  echo "--- $label ---"
  echo "Directory:  $dir"
  echo "Retention:  ${RETENTION_MINUTES} minutes"

  local deleted
  deleted=$(find "$dir" -type f -mmin +"$RETENTION_MINUTES" -print -delete 2>&1)

  if [ -n "$deleted" ]; then
    echo "Deleted:"
    echo "$deleted"
  else
    echo "No files to delete."
  fi

  local empties
  empties=$(find "$dir" -type d -empty -delete -print 2>&1)

  if [ -n "$empties" ]; then
    echo "Removed empty directories:"
    echo "$empties"
  else
    echo "No empty directories to clean."
  fi
}

echo "=== PetCam Cleanup ==="

if guard_directory "$RECORDINGS_DIR"; then
  clean_directory "Recordings" "$RECORDINGS_DIR"
fi

if guard_directory "$PLAYBACK_CACHE_DIR"; then
  clean_directory "Playback cache" "$PLAYBACK_CACHE_DIR"
fi

echo ""
echo "Cleanup complete."
