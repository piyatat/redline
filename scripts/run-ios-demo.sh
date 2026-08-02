#!/usr/bin/env bash
# Build, install, and launch the iOS demo on a Simulator.
#
# Default: pick booted (else any) iPhone Simulator → xcodebuild → simctl install/launch
#   ./scripts/run-ios-demo.sh
# Prefer a name substring:
#   ./scripts/run-ios-demo.sh "iPhone 17"
# Xcode workspace only (no build/run):
#   ./scripts/run-ios-demo.sh --open
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEMO="$ROOT/examples/iOSDemo"
WORKSPACE="$DEMO/iOSDemo.xcworkspace"
PROJECT="$DEMO/iOSDemo.xcodeproj"
SCHEME="iOSDemo"
BUNDLE_ID="dev.redline.iOSDemo"

if [[ "${1:-}" == "--open" ]]; then
  open "$WORKSPACE" 2>/dev/null || open "$PROJECT"
  exit 0
fi

PREFERRED="${1:-}"

if [[ -d "$WORKSPACE" ]]; then
  BUILD_ROOT=(-workspace "$WORKSPACE")
else
  BUILD_ROOT=(-project "$PROJECT")
fi

pick_simulator() {
  # Prefer an already-booted iPhone.
  local booted
  booted="$(xcrun simctl list devices available \
    | awk -F'[()]' '/iPhone/ && /Booted/{gsub(/^[[:space:]]+/,"",$1); gsub(/[[:space:]]+$/,"",$1); print $2 "|" $1; exit}')"
  if [[ -n "$booted" ]]; then
    echo "$booted"
    return
  fi

  local list
  list="$(xcrun simctl list devices available \
    | awk -F'[()]' '/iPhone/ && /\(Shutdown\)|\(Booted\)/{
        name=$1; id=$2
        gsub(/^[[:space:]]+/,"",name); gsub(/[[:space:]]+$/,"",name)
        print id "|" name
      }')"

  if [[ -n "$PREFERRED" ]]; then
    local match
    match="$(printf '%s\n' "$list" | awk -F'|' -v p="$PREFERRED" 'tolower($2) ~ tolower(p) {print; exit}')"
    if [[ -n "$match" ]]; then
      echo "$match"
      return
    fi
    echo "warning: no simulator matching '$PREFERRED' — falling back" >&2
  fi

  # Prefer iPhone 17 / 16-class, else first iPhone.
  local prefer
  prefer="$(printf '%s\n' "$list" | awk -F'|' '/iPhone 17 Pro[^ ]*$/{print; exit}')"
  [[ -z "$prefer" ]] && prefer="$(printf '%s\n' "$list" | awk -F'|' '/iPhone 17[^ ]*$/{print; exit}')"
  [[ -z "$prefer" ]] && prefer="$(printf '%s\n' "$list" | head -1)"
  echo "$prefer"
}

SIM_LINE="$(pick_simulator)"
if [[ -z "$SIM_LINE" || "$SIM_LINE" == "|" ]]; then
  echo "error: no available iPhone Simulator — open Xcode → Window → Devices and Simulators" >&2
  exit 1
fi
SIM_UDID="${SIM_LINE%%|*}"
SIM_NAME="${SIM_LINE#*|}"

echo "Simulator: $SIM_NAME ($SIM_UDID)"
STATE="$(xcrun simctl list devices | awk -v id="$SIM_UDID" '$0 ~ id { if ($0 ~ /Booted/) print "Booted"; else print "Shutdown"; exit }')"
if [[ "$STATE" != "Booted" ]]; then
  echo "Booting simulator…"
  xcrun simctl boot "$SIM_UDID" || true
fi
open -a Simulator --args -CurrentDeviceUDID "$SIM_UDID" >/dev/null 2>&1 || open -a Simulator

echo "Building iOSDemo…"
xcodebuild \
  "${BUILD_ROOT[@]}" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" \
  -quiet \
  build

APP="$(
  xcodebuild \
    "${BUILD_ROOT[@]}" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$SIM_UDID" \
    -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/^[ ]*BUILT_PRODUCTS_DIR /{dir=$2} /^[ ]*FULL_PRODUCT_NAME /{name=$2} END{print dir "/" name}'
)"

if [[ ! -d "$APP" ]]; then
  echo "error: built app not found (Missing package product? try --open and Reset Package Caches)" >&2
  exit 1
fi

echo "Installing $APP"
xcrun simctl install "$SIM_UDID" "$APP"
echo "Launching $BUNDLE_ID"
xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"
echo "Done. Start Redline.app if needed: ./scripts/run-mac-app.sh"
