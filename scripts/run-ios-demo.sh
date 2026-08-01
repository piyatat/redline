#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEMO="$ROOT/examples/iOSDemo"

echo "Open the Xcode app project (not Package.swift):"
echo "  $DEMO/iOSDemo.xcworkspace"
echo "  (or $DEMO/iOSDemo.xcodeproj)"
echo ""
echo "Select scheme iOSDemo → iPhone Simulator → Run."
echo "Ensure Redline Mac app is running: ./scripts/run-mac-app.sh"
echo ""
echo "If 'Missing package product RedlineServer':"
echo "  File → Packages → Reset Package Caches, then Resolve Package Versions"
echo ""

open "$DEMO/iOSDemo.xcworkspace" 2>/dev/null || open "$DEMO/iOSDemo.xcodeproj" 2>/dev/null || echo "Project: $DEMO/iOSDemo.xcodeproj"
