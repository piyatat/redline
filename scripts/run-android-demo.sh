#!/usr/bin/env bash
# Build the Android library + demo; install/launch when an adb device is online.
#
# Default: assembleDebug → adb reverse :8765 → installDebug → start MainActivity
#   ./scripts/run-android-demo.sh
# Assemble only (no install):
#   ./scripts/run-android-demo.sh --assemble-only
#
# Networking: emulator defaults to 10.0.2.2:8765 (host Mac). Physical devices use
# 127.0.0.1 + adb reverse (script always runs reverse; harmless on emulator).
# Gradle root is android/ (modules :redline-android and :AndroidDemo).
# Open android/ in Android Studio — not a nested module folder alone.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/android"
if [[ ! -f local.properties ]]; then
  SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
  echo "sdk.dir=$SDK" > local.properties
fi

ASSEMBLE_ONLY=0
if [[ "${1:-}" == "--assemble-only" ]]; then
  ASSEMBLE_ONLY=1
  shift
fi

echo "Building :redline-android + :AndroidDemo…"
./gradlew :redline-android:assembleDebug :AndroidDemo:assembleDebug "$@"

if [[ "$ASSEMBLE_ONLY" -eq 1 ]]; then
  echo "Assemble-only done. APK under android/AndroidDemo/build/outputs/apk/debug/"
  exit 0
fi

ADB="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}/platform-tools/adb"
if [[ ! -x "$ADB" ]]; then
  ADB="$(command -v adb || true)"
fi
if [[ -z "${ADB:-}" || ! -x "$ADB" ]]; then
  echo "warning: adb not found — open android/ in Android Studio to Run" >&2
  exit 0
fi

DEVICES="$("$ADB" devices | awk 'NR>1 && $2=="device"{print $1}')"
if [[ -z "$DEVICES" ]]; then
  cat <<'EOF'
No adb device/emulator online.
  1. Start an emulator (or plug in a device)
  2. Re-run: ./scripts/run-android-demo.sh
     Emulator → 10.0.2.2 automatically; device → script runs adb reverse
     or: cd android && ./gradlew :AndroidDemo:installDebug
EOF
  exit 0
fi

echo "adb reverse tcp:8765 tcp:8765  (needed for physical devices; optional on emulator)"
"$ADB" reverse tcp:8765 tcp:8765 || true

echo "Installing + launching AndroidDemo…"
./gradlew :AndroidDemo:installDebug
"$ADB" shell am start -n "dev.redline.android.demo/.MainActivity" >/dev/null

cat <<'EOF'
Launched AndroidDemo.
Start Redline.app on the Mac if needed: ./scripts/run-mac-app.sh
Docs: docs/android-setup.md
EOF
