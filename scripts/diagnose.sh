#!/bin/bash
set -euo pipefail

echo "=== PetCam Diagnostics ==="
echo ""

SERVICES=("petcam-mediamtx.service" "petcam-stream.service" "petcam-api.service" "petcam-cleanup.timer")

for svc in "${SERVICES[@]}"; do
  echo "--- $svc ---"
  systemctl status "$svc" 2>&1 | head -15
  echo ""
  echo "Recent journal ($svc):"
  journalctl -u "$svc" --no-pager -n 20 2>&1
  echo ""
done

echo "--- Camera Devices ---"
v4l2-ctl --list-devices 2>&1 || true
echo ""

echo "--- Disk Usage ---"
df -h /opt/petcam/data 2>&1
echo ""

echo "--- Recent Recordings ---"
find /opt/petcam/data/recordings -type f -name "*.mp4" -printf "%T@ %p\n" 2>/dev/null | sort -rn | head -10 | awk '{print strftime("%Y-%m-%d %H:%M:%S",$1), $2}'
echo ""

echo "=== End ==="
