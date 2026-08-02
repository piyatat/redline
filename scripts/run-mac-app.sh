#!/usr/bin/env bash
# Build and launch Redline.app on this Mac (receiver on 127.0.0.1:8765).
#
# Default: xcodebuild Debug → quit previous Redline → open the built .app
#   ./scripts/run-mac-app.sh
# Xcode only (no build/run):
#   ./scripts/run-mac-app.sh --open
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJ="$ROOT/Apps/Redline/Redline.xcodeproj"
SCHEME="Redline"
BUNDLE_ID="dev.redline.app"

if [[ "${1:-}" == "--open" ]]; then
  open "$PROJ"
  exit 0
fi

if [[ ! -d "$PROJ" ]]; then
  echo "error: missing $PROJ" >&2
  exit 1
fi

echo "Building Redline (macOS)…"
xcodebuild \
  -project "$PROJ" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination 'platform=macOS' \
  -quiet \
  build

APP="$(
  xcodebuild \
    -project "$PROJ" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination 'platform=macOS' \
    -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/^[ ]*BUILT_PRODUCTS_DIR /{dir=$2} /^[ ]*FULL_PRODUCT_NAME /{name=$2} END{print dir "/" name}'
)"

if [[ ! -d "$APP" ]]; then
  echo "error: built app not found" >&2
  exit 1
fi

# Relaunch so a previous instance does not keep the old binary.
if pgrep -xq "Redline" 2>/dev/null; then
  echo "Quitting existing Redline…"
  osascript -e 'tell application "Redline" to quit' 2>/dev/null || true
  # Wait briefly for quit; force if still up.
  for _ in 1 2 3 4 5; do
    pgrep -xq "Redline" || break
    sleep 0.2
  done
  pgrep -xq "Redline" && killall Redline 2>/dev/null || true
fi

echo "Launching $APP"
open "$APP"
echo "Receiver: http://127.0.0.1:8765/feedback  ($BUNDLE_ID)"
