# Integrate Redline into your app

Add Redline to an **iOS** or **Android** host so designers can mark up screens and **Send** feedback to **Redline.app** on your Mac.

**Quick start lives in the [README](../README.md#quick-start).** This page covers full options.

| | iOS | Android |
|--|-----|---------|
| Library | SPM `RedlineServer` | Gradle `:redline-android` |
| UI | SwiftUI | Jetpack Compose |
| Entry point | `.designerOverlay()` | `DesignerOverlay { }` |
| Default URL | `http://127.0.0.1:8765/feedback` | Emulator `10.0.2.2` · device `127.0.0.1` + `adb reverse` |
| Toggle designer | Two-finger long-press (~0.45s) or your own button | Same |

Debug builds only — overlay install is a no-op (or skipped) in Release.

You only need the overlay. It installs transport, gestures, and designer state on appear/composition. Optional `Redline.install(…)` remains for advanced pre-configuration.

---

## Full integration — iOS

### Add the package

1. Xcode → **File → Add Package Dependencies…**
2. **Add Local…** → choose the `redline` repo root (`Package.swift`).
3. Add **`RedlineServer`** to your app target.

Or Git: `https://github.com/piyatat/redline.git` → product `RedlineServer`.

### Wrap the root

```swift
import RedlineServer

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .designerOverlay(
                    // context: MyDesignerContext(),
                    // feedbackBaseURL: nil,
                    // inspectPort: 47164
                )
        }
    }
}
```

### Tag regions

```swift
VStack { … }
    .redlineRegion("Header")
```

Untagged screens can still use **Whole screen**.

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

// …
.designerOverlay(context: MyDesignerContext())
```

### API token (when Mac Settings has one)

Set scheme env `REDLINE_API_TOKEN` (and optionally `REDLINE_FEEDBACK_URL`).

### Networking

| Host | Notes |
|------|--------|
| **Simulator** | Reaches Mac `127.0.0.1:8765` automatically |
| **Physical device** | See [device-setup.md](device-setup.md) |

### Reference

- Demo: [`examples/iOSDemo`](../examples/iOSDemo)
- Run: `./scripts/run-ios-demo.sh`

---

## Full integration — Android

Requires **Jetpack Compose**.

### Include the library

```kotlin
// settings.gradle.kts
include(":redline-android")
project(":redline-android").projectDir =
    file("../redline/android/redline-android")
```

```kotlin
// app/build.gradle.kts
dependencies {
    debugImplementation(project(":redline-android"))
}
```

### Cleartext + INTERNET

```xml
<!-- res/xml/network_security_config.xml -->
<network-security-config>
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="false">127.0.0.1</domain>
        <domain includeSubdomains="false">localhost</domain>
        <domain includeSubdomains="false">10.0.2.2</domain>
    </domain-config>
</network-security-config>
```

```xml
<uses-permission android:name="android.permission.INTERNET" />
<application android:networkSecurityConfig="@xml/network_security_config" …>
```

No custom `Application` class is required.

### Root overlay

```kotlin
setContent {
    MaterialTheme {
        DesignerOverlay(
            // context = MyDesignerContext,
            // apiToken = "same-as-Mac-Settings",
            // feedbackBaseUrl = "http://10.0.2.2:8765/feedback",
        ) {
            HomeScreen()
        }
    }
}
```

```kotlin
Text("Title", modifier = Modifier.redlineRegion("Header"))
```

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

### Reference

- Demo: [`android/AndroidDemo`](../android/AndroidDemo)
- Run: `./scripts/run-android-demo.sh`
- Demo notes: [android-setup.md](android-setup.md)

---

## Designer workflow

1. Start **Redline.app** (`./scripts/run-mac-app.sh`).
2. Launch a **Debug** build.
3. **Two-finger long-press** (~0.45s) (or a demo-style button).
4. Tap a region or **Whole screen** → draw → comment → **Send**.
5. Inbox **Composite** is the PNG with strokes baked in.

---

## Checklist

- [ ] Redline.app running
- [ ] Library linked Debug-only
- [ ] Root `.designerOverlay()` / `DesignerOverlay { }`
- [ ] Optional `redlineRegion` tags (or Whole screen)
- [ ] Android cleartext for `127.0.0.1` / `10.0.2.2`
- [ ] API token match when Settings requires one

---

## Troubleshooting

| Symptom | Likely cause |
|---------|----------------|
| Android emulator connect fail | Need `10.0.2.2` (library default) |
| Physical Android connect fail | `adb reverse tcp:8765 tcp:8765` |
| Cleartext blocked | Missing `network_security_config` |
| Empty Inbox | Redline.app down or token mismatch |

---

## Related

- [README quick start](../README.md#quick-start)
- [device-setup.md](device-setup.md)
- [android-setup.md](android-setup.md)
- [agent-wiring.md](agent-wiring.md)
