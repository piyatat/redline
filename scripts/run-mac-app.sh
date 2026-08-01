#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/Apps/Redline"

echo "Open the Redline macOS app project:"
echo "  $APP/Redline.xcodeproj"
echo ""
echo "Select scheme Redline → My Mac → Run."
echo "Receiver listens on http://127.0.0.1:8765"
echo ""

open "$APP/Redline.xcodeproj" 2>/dev/null || echo "Project: $APP/Redline.xcodeproj"
