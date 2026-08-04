# Android setup

Redline Android captures designer feedback (Feedback v1) and POSTs it to **Redline.app** on the Mac — same protocol as iOS.

## Open the project

```bash
open -a "Android Studio" android/
# or: File → Open → redline/android
```

Open the **`android/`** folder (contains `settings.gradle.kts` and `gradlew`). Do **not** open `android/AndroidDemo` alone. If Sync still fails, use **File → Open** on `android/` again (close any project that was pointed at `examples/AndroidDemo`).

Modules:

| Module | Role |
|--------|------|
| `:redline-android` | Debug capture library (Compose overlay + transport) |
| `:AndroidDemo` | Sample host app (`android/AndroidDemo`) |

## Networking (emulator vs device)

| Host | Default feedback URL | Notes |
|------|----------------------|--------|
| **Android emulator** | `http://10.0.2.2:8765/feedback` | Emulator alias for the **Mac** loopback (same idea as iOS Simulator → `127.0.0.1`) |
| **Physical device** | `http://127.0.0.1:8765/feedback` | Needs `adb reverse tcp:8765 tcp:8765` |

Override anytime with `Redline.install(…, feedbackBaseUrl = "…")` or `REDLINE_FEEDBACK_URL`.

## Run the demo

Preferred (builds, `adb reverse` when a **device** is online, installs, launches):

```bash
./scripts/run-mac-app.sh          # Mac receiver first
./scripts/run-android-demo.sh     # assemble + install + launch
```

- `--assemble-only` — build APKs without install
- No emulator/device online → assemble still succeeds; script prints next steps

Manual path:

1. Start **Redline.app** (`./scripts/run-mac-app.sh`).
2. **Physical device only** — forward loopback:

```bash
adb reverse tcp:8765 tcp:8765
```

(Emulator does **not** need `adb reverse` when using the default `10.0.2.2` URL.)

3. Run **AndroidDemo** (Debug) — Android Studio, or `cd android && ./gradlew :AndroidDemo:installDebug`.
4. **Two-finger long-press** (~0.45s) or tap **Enter designer** → pick a region (or **Whole screen**) → draw / write feedback → **Send**.
5. Confirm the item appears in the Mac Inbox with `platform: android`.

Without the right host (`10.0.2.2` on emulator, or `adb reverse` on device), POSTs never reach Redline.app.

## Host app integration

```kotlin
// Application.onCreate() — Debug builds only
Redline.install(
    application = this,
    screen = "home",
    spec = "screens/home.screen.md",
    context = MyDesignerContext, // optional pins
    // feedbackBaseUrl = "http://127.0.0.1:8765/feedback", // optional override
    // apiToken = "same-as-Mac-Settings", // required when Mac API token is set
)
```

Root Compose:

```kotlin
DesignerOverlay(screen = "home", spec = "…", context = MyDesignerContext) {
    HomeScreen()
}
```

Tag regions:

```kotlin
modifier.redlineRegion("Header")
```

Gradle (settings include the library project, or publish locally later):

```kotlin
dependencies {
    debugImplementation(project(":redline-android"))
}
```

Optional process env (rarely set on stock Android — prefer `install(feedbackBaseUrl=…, apiToken=…)` or instrumentation):

```
REDLINE_FEEDBACK_URL=http://127.0.0.1:8765/feedback
REDLINE_API_TOKEN=your-token
```

Host apps must declare `INTERNET` and allow cleartext to `127.0.0.1` **and** `10.0.2.2` (see demo `network_security_config.xml`). Use `debugImplementation` for the library in production hosts.

## What this ships

- Designer mode toggle (two-finger long-press or button), region tags, markup (pen / arrow / rect), top frosted toolbar with show/hide → **Send** → Feedback v1
- **Composite PNG** with markup strokes baked in (same image Mac Inbox and agents use), plus stroke JSON, optional pins, and a small runtime block

## Not in this slice

- Hierarchy TCP (iOS-only; not shipped on Android)
- Maven Central publish
- View-system (non-Compose) hosts
