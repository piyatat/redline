# Physical device setup

Redline inspects iOS apps over TCP. Simulator apps use ports **47164–47169** on `127.0.0.1`. Physical devices use **47175–47179** over USB (USB TCP forwarding).

## Simulator (default)

No extra setup. iOS POSTs feedback to `http://127.0.0.1:8765/feedback` automatically. Redline.app’s receiver binds **loopback only** (`127.0.0.1`).

## Physical device — inspector

1. Build and run your app on device with `Redline.install()` (Debug).
2. Forward a **Mac → device** inspect port with stock `iproxy` (host listens, traffic goes to the phone):

```bash
iproxy 47175 47175
```

3. Point hierarchy tools / MCP `redline_get_tree` at `127.0.0.1:47175`. If the tree is empty, verify the device is trusted and the debug build is running.

## Physical device — feedback POST

The Mac receiver listens on **`127.0.0.1:8765` only**. The device cannot reach that address with stock `iproxy`, which only forwards **Mac → device** (and would conflict if you tried `iproxy 8765 8765` while Redline already owns `:8765`).

**Practical options:**

1. **Prefer the Simulator** for Save → Inbox feedback during day-to-day work.
2. **USB reverse tunnel** — use a tool that maps **device → Mac loopback** `:8765` (not stock `iproxy`). Then keep:

```
REDLINE_FEEDBACK_URL=http://127.0.0.1:8765/feedback
```

3. If you use a reverse tunnel or future LAN-bind option, set an **API token** in Redline Settings and the same `REDLINE_API_TOKEN` on the device scheme.

```
REDLINE_API_TOKEN=your-token
```

## USB inspect port in host app

Optional: bind inspector to USB range in Debug:

```swift
Redline.install(inspectPort: 47175)
```
