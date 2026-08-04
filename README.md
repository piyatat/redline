# Redline

Debug-only **designer feedback** capture for **iOS** and **Android**: mark up a screen, **Send** to a native **macOS** Inbox, then trigger Cursor/Claude agents (CLI or MCP).

## Components

| Module | Platform | Description |
|--------|----------|-------------|
| `RedlineShared` | iOS + macOS | Protocol models, Feedback v1, gates, agent prompts (SPM) |
| `RedlineServer` | iOS | Embed in host apps — designer markup → POST feedback (SPM) |
| `android/redline-android` | Android | Debug capture library — Compose markup → Feedback v1 |
| `Apps/Redline` | macOS | **Redline.app** — Inbox · HTTP receiver · agent wiring |
| `redline` (CLI) | macOS | `inbox`, `gates`, `mcp`, optional `inspect` |
| `examples/iOSDemo` | iOS | Demo host — `./scripts/run-ios-demo.sh` |
| `android/AndroidDemo` | Android | Demo host — `./scripts/run-android-demo.sh` (open `android/` in Android Studio) |

## Build & run

```bash
# Shared libraries + CLI
swift build --product redline
swift test

# Mac app (build + launch receiver on 127.0.0.1:8765)
./scripts/run-mac-app.sh
# or: ./scripts/run-mac-app.sh --open   # Xcode only

# iOS demo (build + Simulator)
./scripts/run-ios-demo.sh
# or: ./scripts/run-ios-demo.sh "iPhone 17"
# or: ./scripts/run-ios-demo.sh --open

# Android demo (build + install/launch if device online)
./scripts/run-android-demo.sh
# or: ./scripts/run-android-demo.sh --assemble-only
# or: open android/ in Android Studio → run AndroidDemo
# Emulator → 10.0.2.2:8765; device → 127.0.0.1 + adb reverse
```

## End-to-end

1. Mac: `./scripts/run-mac-app.sh` (listens on `127.0.0.1:8765`)
2. Host: `./scripts/run-ios-demo.sh` **or** `./scripts/run-android-demo.sh`
3. Designer: mark up → **Send** → Mac **Inbox** (composite PNG includes baked strokes)
4. Settings → Cursor Agent CLI / Claude Code / desktop MCP. See [docs/agent-wiring.md](docs/agent-wiring.md)
5. Devices: [docs/device-setup.md](docs/device-setup.md) · Android: [docs/android-setup.md](docs/android-setup.md)

## Gates

Optional validation of feedback bundles. Default gate: `scripts/validate-feedback.mjs` (see `scripts/gate-manifest.json`). Override with `REDLINE_GATE_MANIFEST`.

```bash
export REDLINE_WORKSPACE_ROOT=/path/to/redline
export REDLINE_BUNDLE_DIR=/path/to/feedback/bundle

./scripts/run-gates.sh "$REDLINE_WORKSPACE_ROOT" "$REDLINE_BUNDLE_DIR"

swift run redline gates run --workspace "$REDLINE_WORKSPACE_ROOT" --bundle "$REDLINE_BUNDLE_DIR"
```

Set `REDLINE_WORKSPACE_ROOT` (CLI/MCP) to the repo containing `scripts/gate-manifest.json` when running gates. The Mac app stores feedback under Application Support and does not require a workspace setting.

## CLI & MCP

```bash
swift run redline health
swift run redline inbox list
swift run redline mcp
```

MCP tools: `redline_wait_for_feedback`, `redline_inbox_set_status`, `redline_inbox_*`, `redline_gates_run`, and (iOS host) `redline_get_tree`.

Cursor desktop MCP + `/redline-wait`: Redline.app **Settings → When feedback arrives → Cursor desktop (MCP)**, then **Install into project…**. Or `swift run redline cursor setup --project …`.

Full setup: [docs/agent-wiring.md](docs/agent-wiring.md) · example config: `.cursor/mcp.json.example`.

### Optional — hierarchy TCP (iOS)

Debug iOS hosts still expose a TCP hierarchy service used by CLI/`redline_get_tree`. There is **no** hierarchy inspector UI in Redline.app right now.

```bash
swift run redline inspect ping --port 47164
```

Ports and USB forwarding: [docs/device-setup.md](docs/device-setup.md). Android does not ship hierarchy TCP.

## Updates

Optional `REDLINE_APPCAST_URL` for distribution feeds (see [docs/appcast-setup.md](docs/appcast-setup.md)). In-app Check for Updates is not wired yet.

## Project status

- [x] R1 — Mac Inbox + designer feedback
- [x] R2 — Bridge / measure / live edit plumbing (Mac hierarchy UI not shown)
- [x] R3 — CLI/MCP, HTTP `/inbox`
- [x] R4 — USB inspect ports, appcast docs, device docs
- [x] R5 — Android Feedback v1 capture (Compose); web capture still open

See the Redline implementation plan in the parent workspace (`doc/plan/`) when present.

## License

MIT
