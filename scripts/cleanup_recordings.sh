#!/bin/bash
set -euo pipefail

RECORDINGS_DIR="${RECORDINGS_DIR:-/opt/petcam/data/recordings}"
RETENTION_MINUTES="${RETENTION_MINUTES:-720}"

if [ -z "$RECORDINGS_DIR" ] || [ ! -d "$RECORDINGS_DIR" ]; then
  echo "ERROR: RECORDINGS_DIR is empty or does not exist: $RECORDINGS_DIR"
  exit 1
fi

if [ "$RECORDINGS_DIR" = "/" ] || [ "$RECORDINGS_DIR" = "/home" ] || [ "$RECORDINGS_DIR" = "/opt" ]; then
  echo "ERROR: RECORDINGS_DIR is a system directory, refusing: $RECORDINGS_DIR"
  exit 1
fi

echo "=== PetCam Recording Cleanup ==="
echo "Directory:  $RECORDINGS_DIR"
echo "Retention:  ${RETENTION_MINUTES} minutes"

# Delete files older than RETENTION_MINUTES
deleted=$(find "$RECORDINGS_DIR" -type f -mmin +"$RETENTION_MINUTES" -print -delete 2>&1)

if [ -n "$deleted" ]; then
  echo "Deleted:"
  echo "$deleted"
else
  echo "No files to delete."
fi

# Remove empty directories
empties=$(find "$RECORDINGS_DIR" -type d -empty -delete -print 2>&1)

if [ -n "$empties" ]; then
  echo "Removed empty directories:"
  echo "$empties"
else
  echo "No empty directories to clean."
fi

echo "Cleanup complete."
