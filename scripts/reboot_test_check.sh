#!/bin/bash
set -euo pipefail

PASS=0
FAIL=0

check() {
  local label="$1"
  shift
  if "$@" 2>/dev/null; then
    echo "  PASS  $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL  $label"
    FAIL=$((FAIL + 1))
  fi
}

wait_for() {
  local label="$1"
  local cmd="$2"
  local timeout="${3:-60}"
  local waited=0
  while [ $waited -lt "$timeout" ]; do
    if eval "$cmd" 2>/dev/null; then
      echo "  PASS  $label (${waited}s)"
      PASS=$((PASS + 1))
      return 0
    fi
    sleep 2
    waited=$((waited + 2))
  done
  echo "  FAIL  $label (timed out after ${timeout}s)"
  FAIL=$((FAIL + 1))
  return 1
}

echo "=== PetCam Reboot Test ==="
echo ""

echo "--- Service status ---"
check "petcam-mediamtx.service is active" systemctl is-active --quiet petcam-mediamtx.service
check "petcam-stream.service is active" systemctl is-active --quiet petcam-stream.service
check "petcam-api.service is active" systemctl is-active --quiet petcam-api.service
check "petcam-cleanup.timer is enabled" systemctl is-enabled --quiet petcam-cleanup.timer
check "petcam-cleanup.timer is active" systemctl is-active --quiet petcam-cleanup.timer

echo ""
echo "--- Endpoint reachability ---"

HLS_M3U8="http://127.0.0.1:8888/cam/index.m3u8"
wait_for "HLS manifest at ${HLS_M3U8} contains #EXTM3U" \
  "curl -fsSL --max-time 10 '${HLS_M3U8}' 2>/dev/null | head -1 | grep -q '^#EXTM3U'" 60 || {
  echo ""
  echo "  --- HLS failure diagnostics ---"
  echo "  HTTP status: $(curl -sL -o /dev/null -w '%{http_code}' '${HLS_M3U8}' 2>/dev/null || echo 'unreachable')"
  echo "  Player page check:"
  if curl -sL --max-time 5 'http://127.0.0.1:8888/cam/' 2>/dev/null | grep -qi "hls"; then
    echo "    /cam/ responds with HLS player HTML"
  else
    echo "    /cam/ does not contain HLS player"
  fi
  echo "  Recent MediaMTX logs:"
  journalctl -u petcam-mediamtx.service --no-pager -n 20 2>/dev/null || true
  echo "  Recent stream logs:"
  journalctl -u petcam-stream.service --no-pager -n 20 2>/dev/null || true
}

wait_for "API health at http://127.0.0.1:8000/health" \
  "curl -fsSL --max-time 10 'http://127.0.0.1:8000/health' | python3 -c \"import sys,json; d=json.load(sys.stdin); exit(0 if d.get('status')=='ok' else 1)\"" 60

echo ""
echo "--- Device access ---"
check "/opt/petcam/data/recordings is writable" sudo -u petcam touch /opt/petcam/data/recordings/.petcam_test
check "cleanup test file removed" sudo -u petcam rm -f /opt/petcam/data/recordings/.petcam_test

echo ""
echo "================"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo "================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
