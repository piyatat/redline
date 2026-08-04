# Device setup

Day-to-day Redline is **designer Send → Mac Inbox**. Redline.app’s receiver binds **loopback only** (`127.0.0.1:8765` on the Mac). iOS Simulator and Android physical devices (via `adb reverse`) POST to that URL; the **Android emulator** POSTs to `http://10.0.2.2:8765/feedback` (guest alias for the Mac).

**New host app?** See **[integration.md](integration.md)** for iOS SPM / Android Gradle wiring.

## Simulator / emulator (default)

```bash
./scripts/run-mac-app.sh      # build + launch Redline.app
./scripts/run-ios-demo.sh     # iOS Simulator
# or
./scripts/run-android-demo.sh # adb reverse + install when a device is online
```

- iOS Simulator reaches Mac loopback automatically.
- Android **emulator** reaches the Mac via `10.0.2.2:8765` automatically (not `127.0.0.1`).
- Android **device** needs `adb reverse tcp:8765 tcp:8765` (the Android run script does this when a device is online). See [android-setup.md](android-setup.md).

Flags: `./scripts/run-ios-demo.sh --open` / `./scripts/run-mac-app.sh --open` open Xcode only; `./scripts/run-android-demo.sh --assemble-only` builds without install.

## Physical device — feedback POST

The Mac receiver listens on **`127.0.0.1:8765` only**. A phone cannot reach that with stock `iproxy` (Mac→device only; also conflicts if Redline already owns `:8765`).

**Practical options:**

1. **Prefer Simulator / emulator** for Send → Inbox.
2. **USB reverse tunnel** — map **device → Mac loopback** `:8765`, then keep:

```
REDLINE_FEEDBACK_URL=http://127.0.0.1:8765/feedback
```

3. With a reverse tunnel (or any shared Mac), set an **API token** in Redline Settings and the same token on the device (`REDLINE_API_TOKEN` / `Redline.install(…, apiToken:)` on Android).

```
REDLINE_API_TOKEN=your-token
```

## Optional — iOS hierarchy TCP

Debug iOS hosts (`Redline.install`) also bind a **hierarchy TCP** port for CLI `inspect` / MCP `redline_get_tree`. This is separate from feedback. **Redline.app does not show a hierarchy UI** today.

| Environment | Ports |
|-------------|-------|
| Simulator | **47164–47169** on `127.0.0.1` |
| Physical (USB) | **47175–47179** via Mac→device forward |

### Physical device — hierarchy

1. Run a Debug host with `Redline.install()` (optionally `inspectPort: 47175`).
2. Forward **Mac → device**:

```bash
iproxy 47175 47175
```

3. Point tools at `127.0.0.1:47175`:

```bash
swift run redline inspect ping --port 47175
```

Optional host override:

```swift
Redline.install(inspectPort: 47175)
```

Android does **not** ship hierarchy TCP.
