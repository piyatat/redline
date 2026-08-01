# Physical device setup

Redline inspects iOS apps over TCP. Simulator apps use ports **47164–47169** on `127.0.0.1`. Physical devices use **47175–47179** over USB (USB TCP forwarding).

## Simulator (default)

No extra setup. iOS POSTs feedback to `http://127.0.0.1:8765/feedback` automatically.

## Physical device — inspector

1. Build and run your app on device with `Redline.install()` (Debug).
2. Redline.app scans USB ports **47175–47179** when you click **Scan for apps**.
3. If the app does not appear, verify the device is trusted and the debug build is running.

## Physical device — feedback POST

The device cannot reach Mac `127.0.0.1` directly. Forward port 8765:

```bash
# Forward Mac receiver port to the device (requires `iproxy`)
iproxy 8765 8765
```

Set in the iOS app (or scheme environment):

```
REDLINE_FEEDBACK_URL=http://127.0.0.1:8765/feedback
```

On device, `127.0.0.1` refers to the device itself, so use your Mac's LAN IP instead when not using iproxy USB tunnel:

```
REDLINE_FEEDBACK_URL=http://192.168.1.x:8765/feedback
```

Ensure Redline.app is running and Mac firewall allows inbound on 8765.

**Security:** LAN exposure of `:8765` is unauthenticated unless you set an **API token** in Redline Settings. Prefer `iproxy` USB forwarding when possible.

If the Mac app has an **API token** set, also export the same value on the device scheme:

```
REDLINE_API_TOKEN=your-token
```

## USB inspect port in host app

Optional: bind inspector to USB range in Debug:

```swift
Redline.install(inspectPort: 47175)
```
