# Redline

Debug-only UI inspector + designer redline capture for iOS, with a native **macOS app** receiver and agent auto-trigger.

## Components

| Module | Platform | Description |
|--------|----------|-------------|
| `RedlineShared` | iOS + macOS | Protocol models, wire codec, gates, agent prompts (SPM) |
| `RedlineServer` | iOS | Embed in host apps — inspector + designer markup (SPM) |
| `Apps/Redline` | macOS | **Redline.app** — Inbox · Agent receiver (`Redline.xcodeproj`) |
| `redline` (CLI) | macOS | `inbox`, `inspect`, `gates`, `mcp` (SPM executable) |
| `examples/iOSDemo` | iOS | Demo host app (`iOSDemo.xcworkspace`) |

## Build

```bash
# Shared libraries + CLI
swift build --product redline
swift test

# Mac app (Xcode project)
./scripts/run-mac-app.sh
# or: open Apps/Redline/Redline.xcodeproj → scheme Redline → My Mac → Run

# iOS demo
./scripts/run-ios-demo.sh
# or: open examples/iOSDemo/iOSDemo.xcworkspace → scheme iOSDemo → Simulator → Run
```

## End-to-end

1. Run Mac app: `./scripts/run-mac-app.sh` → Run (listens on `:8765`)
2. Run iOS demo: `./scripts/run-ios-demo.sh` → Simulator
3. Designer: save redline on device → Mac **Inbox** (composite, comment, **Send to AI**)
4. Configure **Settings** → Cursor Agent CLI or Claude Code CLI + project folder. See [docs/agent-wiring.md](docs/agent-wiring.md)
5. USB devices / feedback forwarding: [docs/device-setup.md](docs/device-setup.md)

> Inspector UI is temporarily hidden in the Mac app; CLI `inspect` / MCP `redline_get_tree` still work against a running host.

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
swift run redline inspect ping --port 47164
swift run redline mcp
```

MCP tools: `redline_wait_for_feedback`, `redline_inbox_set_status`, `redline_inbox_*`, `redline_get_tree`, `redline_gates_run`.

Cursor desktop MCP + `/redline-wait`: Redline.app **Settings → When feedback arrives → Cursor desktop (MCP)**, then **Install into project…**. Or `swift run redline cursor setup --project …`.

Full setup: [docs/agent-wiring.md](docs/agent-wiring.md) · example config: `.cursor/mcp.json.example`.

## Updates

Optional `REDLINE_APPCAST_URL` for distribution feeds (see [docs/appcast-setup.md](docs/appcast-setup.md)). In-app Check for Updates is not wired yet.

## Project status

- [x] R1 — Mac app MVP + designer feedback
- [x] R2 — Bridge, measure, live edit, SceneKit preview, export
- [x] R3 — CLI/MCP, HTTP `/inbox`
- [x] R4 — Fast mode, console, per-node refresh, USB inspect ports, appcast docs, device docs
- [ ] R5 — Android / web capture

See the Redline implementation plan in the parent workspace (`doc/plan/`) when present.

## License

MIT
