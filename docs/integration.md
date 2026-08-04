# Integrate Redline into your app

Add Redline to an **iOS** or **Android** host so designers can mark up screens and **Send** feedback to **Redline.app** on your Mac.

| | iOS | Android |
|--|-----|---------|
| Library | SPM `RedlineServer` | Gradle `:redline-android` |
| UI | SwiftUI | Jetpack Compose |
| Default URL | `http://127.0.0.1:8765/feedback` | Emulator `10.0.2.2` · device `127.0.0.1` + `adb reverse` |
| Toggle designer | Two-finger long-press (~0.45s) or your own button | Same |

Debug builds only — `install` is a no-op (or skipped) in Release.

---

## Quick start

### 0. Mac receiver

```bash
# From this redline checkout
./scripts/run-mac-app.sh
```

Confirm the status line shows listening on `127.0.0.1:8765`.

### 1a. iOS (Simulator)

1. Xcode → your app target → **Package Dependencies** → **Add Local…** → select the `redline` folder (the one with `Package.swift`).
2. Add product **`RedlineServer`** to the app target.
3. In `App` init (Debug only):

```swift
import RedlineServer

#if DEBUG
Redline.install(screen: "home", spec: "screens/home.screen.md")
#endif
```

4. Wrap the root view:

```swift
ContentView()
    .designerOverlay(screen: "home", spec: "screens/home.screen.md")
```

5. Tag a region (optional but useful):

```swift
HeaderView()
    .redlineRegion("Header")
```

6. Run on **Simulator** → two-finger long-press → **Whole screen** (or a region) → draw / comment → **Send**.

### 1b. Android (emulator)

1. In your app’s `settings.gradle.kts`:

```kotlin
include(":redline-android")
project(":redline-android").projectDir =
    file("/ABSOLUTE/PATH/TO/redline/android/redline-android")
```

2. In the app module `build.gradle.kts`:

```kotlin
dependencies {
    debugImplementation(project(":redline-android"))
}
```

3. Manifest: `INTERNET` + cleartext to Mac hosts (copy from [network_security_config.xml](../android/AndroidDemo/src/main/res/xml/network_security_config.xml)):

```xml
<uses-permission android:name="android.permission.INTERNET" />
<!-- application android:networkSecurityConfig="@xml/network_security_config" -->
```

4. `Application.onCreate()`:

```kotlin
Redline.install(
    application = this,
    screen = "home",
    spec = "screens/home.screen.md",
)
```

5. Root Compose:

```kotlin
DesignerOverlay(screen = "home", spec = "screens/home.screen.md") {
    HomeScreen()
}
```

6. Tag a region:

```kotlin
modifier.redlineRegion("Header")
```

7. Run on an **emulator** → two-finger long-press → markup → **Send**  
   (defaults to `http://10.0.2.2:8765/feedback` — no `adb reverse` needed).

### 2. Confirm

Inbox in Redline.app should show the item with a **Composite** PNG that includes your markup strokes.

Next: [agent-wiring.md](agent-wiring.md) to run Cursor/Claude on feedback · [device-setup.md](device-setup.md) for physical devices.

---

## Full integration — iOS

### Add the package

**Local path (recommended while developing Redline):**

1. Xcode → **File → Add Package Dependencies…**
2. **Add Local…** → choose the `redline` repo root (`Package.swift`).
3. Add **`RedlineServer`** to your **Debug** app target (not a Release-only target if you can avoid it — `install` already guards with `#if DEBUG`).

**Git URL** (when you pin a revision):

```
https://github.com/piyatat/redline.git
```

Product: `RedlineServer` (pulls in `RedlineShared`).

### Install

Call once at launch, behind `#if DEBUG`:

```swift
import RedlineServer

@main
struct MyApp: App {
    init() {
        #if DEBUG
        Redline.install(
            screen: "home",                    // logical screen id
            spec: "screens/home.screen.md",    // path agents should edit (optional)
            state: nil,                        // optional UI state label
            context: MyDesignerContext(),      // optional pins
            feedbackBaseURL: nil,              // default http://127.0.0.1:8765/feedback
            inspectPort: 47164                 // optional hierarchy TCP (Simulator)
        )
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .designerOverlay(
                    screen: "home",
                    spec: "screens/home.screen.md",
                    context: MyDesignerContext()
                )
        }
    }
}
```

`designerOverlay` adds the designer banner + markup UI. Keep `screen` / `spec` in sync with `install` (or call `Redline.updateScreen` on navigation).

### Tag regions

```swift
VStack { … }
    .redlineRegion("Header")

PrimaryButton(…)
    .redlineRegion("CTA")
```

In designer mode, tagged views get an orange outline and open markup on tap. Untagged screens can still use **Whole screen**.

### Optional pins

```swift
import RedlineShared

struct MyDesignerContext: DesignerContext {
    func pins(screen: String, region: String) -> [DesignerPin] {
        switch region {
        case "CTA":
            return [DesignerPin(component: "Button", pin: "color=primary")]
        default:
            return []
        }
    }
}
```

### API token (when Mac Settings has one)

iOS reads `REDLINE_API_TOKEN` from the process environment. In Xcode: **Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables**.

```
REDLINE_API_TOKEN=same-value-as-Redline-Settings
```

Optional override:

```
REDLINE_FEEDBACK_URL=http://127.0.0.1:8765/feedback
```

### Networking

| Host | Notes |
|------|--------|
| **Simulator** | Reaches Mac `127.0.0.1:8765` automatically |
| **Physical device** | Loopback on the phone is not the Mac — see [device-setup.md](device-setup.md) |

### Reference

- Demo: [`examples/iOSDemo`](../examples/iOSDemo)
- Run demo: `./scripts/run-ios-demo.sh`

---

## Full integration — Android

Requires **Jetpack Compose**. View-system hosts are not supported yet.

### Include the library

Point Gradle at this checkout’s Android library module:

```kotlin
// settings.gradle.kts (app repo)
include(":redline-android")
project(":redline-android").projectDir =
    file("../redline/android/redline-android") // adjust relative/absolute path
```

```kotlin
// app/build.gradle.kts
dependencies {
    debugImplementation(project(":redline-android"))
}
```

Use **`debugImplementation`** so Release APKs never ship the capture library.

The library expects a Compose BOM / Material3 stack compatible with this repo’s `android/gradle/libs.versions.toml` (Compose BOM ~2024.12, minSdk 26).

### Cleartext + INTERNET

Redline.app speaks **HTTP** on loopback. Allow cleartext **only** to those hosts:

`res/xml/network_security_config.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="false">127.0.0.1</domain>
        <domain includeSubdomains="false">localhost</domain>
        <domain includeSubdomains="false">10.0.2.2</domain>
    </domain-config>
</network-security-config>
```

`AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<application
    android:name=".MyApplication"
    android:networkSecurityConfig="@xml/network_security_config"
    …>
```

### Install

```kotlin
class MyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        Redline.install(
            application = this,
            screen = "home",
            spec = "screens/home.screen.md",
            context = MyDesignerContext,
            // feedbackBaseUrl = "http://10.0.2.2:8765/feedback", // optional
            // apiToken = "same-as-Mac-Settings",                 // when Settings has a token
        )
    }
}
```

`install` no-ops when the app is not debuggable.

### Root overlay + regions

```kotlin
setContent {
    MaterialTheme {
        DesignerOverlay(
            screen = "home",
            spec = "screens/home.screen.md",
            context = MyDesignerContext,
        ) {
            HomeScreen()
        }
    }
}
```

```kotlin
Text("Title", modifier = Modifier.redlineRegion("Header"))
```

On navigation, call `Redline.updateScreen(screen = "…", spec = "…")`.

### Optional pins

```kotlin
object MyDesignerContext : DesignerContext {
    override fun pins(screen: String, region: String): List<DesignerPin> =
        when (region) {
            "CTA" -> listOf(DesignerPin(component = "Button", pin = "color=primary"))
            else -> emptyList()
        }
}
```

### Networking

| Host | Default URL | Extra step |
|------|-------------|------------|
| **Emulator** | `http://10.0.2.2:8765/feedback` | None |
| **Physical device** | `http://127.0.0.1:8765/feedback` | `adb reverse tcp:8765 tcp:8765` |

Override with `feedbackBaseUrl` / `REDLINE_FEEDBACK_URL`. Prefer `apiToken =` on `install` over process env on stock devices.

### Reference

- Demo module: [`android/AndroidDemo`](../android/AndroidDemo)
- Open Gradle root: `android/` in Android Studio
- Run demo: `./scripts/run-android-demo.sh`
- Demo-focused notes: [android-setup.md](android-setup.md)

---

## Designer workflow (both platforms)

1. Start **Redline.app** on the Mac.
2. Launch a **Debug** build of the host.
3. **Two-finger long-press** (~0.45s) to enter designer mode (or wire `DesignerModeController` / a button like the demos).
4. Tap an orange region or **Whole screen**.
5. Draw (pen / arrow / rect), write a comment, **Send**.
6. Use the toolbar **hide** control to mark up under the chrome; canvas stays drawable.
7. Mac Inbox shows the item; **Composite** is the device screenshot **with strokes baked in** (same PNG agents read).

---

## Checklist

- [ ] Redline.app running (`./scripts/run-mac-app.sh`)
- [ ] Library linked **Debug-only** (`RedlineServer` / `debugImplementation`)
- [ ] `Redline.install` + root overlay (`designerOverlay` / `DesignerOverlay`)
- [ ] At least one `redlineRegion` **or** use Whole screen
- [ ] Android: `INTERNET` + cleartext for `127.0.0.1` / `10.0.2.2`
- [ ] Same API token on Mac Settings and device when required
- [ ] Emulator/device networking correct ([device-setup.md](device-setup.md))

---

## Troubleshooting

| Symptom | Likely cause |
|---------|----------------|
| Send fails / connection error (Android emulator) | Still posting to `127.0.0.1` — reinstall library so default is `10.0.2.2`, or set `feedbackBaseUrl` |
| Send fails (physical Android) | Missing `adb reverse tcp:8765 tcp:8765` |
| HTTP cleartext blocked | Missing `network_security_config` domains |
| Nothing in Inbox | Redline.app not running, or API token mismatch |
| Clean screenshot, no lines | Update to a build that bakes strokes into `composite.png` |
| `install` does nothing | Release / non-debuggable build |

---

## Related

- [device-setup.md](device-setup.md) — Simulator / emulator / USB
- [android-setup.md](android-setup.md) — Android demo project
- [agent-wiring.md](agent-wiring.md) — Cursor / Claude after Send
- Demos: `./scripts/run-ios-demo.sh` · `./scripts/run-android-demo.sh`
