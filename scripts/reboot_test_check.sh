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
wait_for "HLS stream at localhost:8888/cam/index.m3u8" \
  "curl -sf http://localhost:8888/cam/index.m3u8 | head -1 | grep -q ."
wait_for "API health at localhost:8000/health" \
  "curl -sf http://localhost:8000/health | python3 -c \"import sys,json; d=json.load(sys.stdin); exit(0 if d.get('status')=='ok' else 1)\""

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
