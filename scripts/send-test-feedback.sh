#!/usr/bin/env bash
# POST sample Feedback v1 payload to a running Redline.app receiver.
set -euo pipefail

PORT="${1:-8765}"
BODY='{
  "schema": 1,
  "screen": "demo-home",
  "region": "CTA",
  "state": "default",
  "platform": "ios",
  "mode": "light",
  "spec": "screens/demo-home.screen.md",
  "capturedTs": "2026-07-06T12:00:00Z",
  "comment": "Make the button full width",
  "pins": [{ "component": "Button", "pin": "fillWidth=true" }],
  "toolsUsed": ["pen"],
  "strokes": [{ "tool": "pen", "color": "red", "points": [[10, 10], [100, 100]] }],
  "compositePngBase64": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
}'

AUTH_ARGS=()
TOKEN="${REDLINE_API_TOKEN:-}"
if [[ -n "${TOKEN}" ]]; then
  AUTH_ARGS=(-H "Authorization: Bearer ${TOKEN}")
fi

curl -sS -X POST "http://127.0.0.1:${PORT}/feedback" \
  -H "Content-Type: application/json" \
  "${AUTH_ARGS[@]}" \
  -d "$BODY"
echo
