#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SERVICES=("petcam-mediamtx.service" "petcam-stream.service" "petcam-api.service" "petcam-cleanup.timer")

echo "=== PetCam Status ==="
echo ""

overall=0

for svc in "${SERVICES[@]}"; do
  state=$(systemctl is-active "$svc" 2>/dev/null || echo "unknown")
  enabled=$(systemctl is-enabled "$svc" 2>/dev/null || echo "unknown")
  if [ "$state" = "active" ]; then
    echo -e "  ${GREEN}active${NC}   ${svc}  (enabled: ${enabled})"
  else
    echo -e "  ${RED}${state}${NC}   ${svc}  (enabled: ${enabled})"
    overall=1
  fi
done

echo ""

echo "--- API Health ---"
if health=$(curl -fsSL --max-time 10 http://127.0.0.1:8000/health 2>/dev/null); then
  status=$(echo "$health" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unknown'))" 2>/dev/null || echo "parse error")
  if [ "$status" = "ok" ]; then
    echo -e "  ${GREEN}ok${NC}"
  else
    echo -e "  ${YELLOW}${status}${NC}"
    overall=1
  fi
else
  echo -e "  ${RED}unreachable${NC}"
  overall=1
fi

echo ""

echo "--- HLS Stream ---"
http_code=$(curl -sL -o /dev/null -w '%{http_code}' http://127.0.0.1:8888/cam/index.m3u8 2>/dev/null || echo "000")
m3u8=$(curl -fsSL --max-time 10 http://127.0.0.1:8888/cam/index.m3u8 2>/dev/null | head -1 || echo "")
if echo "$m3u8" | grep -q "^#EXTM3U"; then
  echo -e "  ${GREEN}responding${NC}  (HTTP ${http_code}, first line: ${m3u8})"
elif [ "$http_code" != "000" ]; then
  echo -e "  ${YELLOW}HTTP ${http_code}${NC}  (expected 200, got redirect/page)"
  overall=1
else
  echo -e "  ${RED}not reachable${NC}"
  overall=1
fi

echo ""

echo "--- Storage ---"
rec_count=$(find /opt/petcam/data/recordings -type f 2>/dev/null | wc -l)
cache_count=$(find /opt/petcam/data/playback-cache -type f 2>/dev/null | wc -l)
echo "  Recordings:      ${rec_count} files"
echo "  Playback cache:  ${cache_count} files"
df -h /opt/petcam/data 2>/dev/null | tail -1 | awk '{print "  Disk usage:      " $3 " / " $2 " (" $5 ")"}'

echo ""

exit $overall
