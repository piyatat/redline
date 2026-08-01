#if os(iOS)
import UIKit
import RedlineShared

enum AppRuntimeContextCapture {
    static func capture(
        userInfo: [String: String]?,
        notes: String?
    ) -> AppRuntimeContext {
        let bundle = Bundle.main
        let device = UIDevice.current
        let screen = UIScreen.main
        let traits = UITraitCollection.current

        let window = keyWindow()
        let root = window?.rootViewController
        let top = topViewController(from: root)
        let navStack = navigationStack(from: root)
        let presented = presentedChain(from: root)

        let stack = Array(Thread.callStackSymbols.prefix(48))

        let bounds = screen.bounds
        let scale = screen.scale
        let boundsDesc = String(
            format: "%.0fx%.0f@%.0fx",
            bounds.width,
            bounds.height,
            scale
        )

        return AppRuntimeContext(
            bundleId: bundle.bundleIdentifier,
            appName: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            deviceModel: deviceModelIdentifier(),
            systemName: device.systemName,
            systemVersion: device.systemVersion,
            isSimulator: isSimulator(),
            localeIdentifier: Locale.current.identifier,
            timeZoneIdentifier: TimeZone.current.identifier,
            screenBounds: boundsDesc,
            orientation: orientationLabel(device.orientation),
            interfaceStyle: traits.userInterfaceStyle == .dark ? "dark" : "light",
            topViewController: describe(top),
            viewControllerStack: navStack,
            presentedChain: presented,
            processId: Int(ProcessInfo.processInfo.processIdentifier),
            threadName: Thread.current.name.flatMap { $0.isEmpty ? nil : $0 } ?? "main",
            callStack: stack,
            userInfo: userInfo.flatMap { $0.isEmpty ? nil : $0 },
            notes: notes.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        )
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first
    }

    private static func topViewController(from root: UIViewController?) -> UIViewController? {
        guard var current = root else { return nil }
        while true {
            if let presented = current.presentedViewController {
                current = presented
                continue
            }
            if let nav = current as? UINavigationController, let visible = nav.visibleViewController {
                current = visible
                continue
            }
            if let tabs = current as? UITabBarController, let selected = tabs.selectedViewController {
                current = selected
                continue
            }
            if let split = current as? UISplitViewController {
                let next = split.viewController(for: .secondary) ?? split.viewControllers.last
                if let next, next !== current {
                    current = next
                    continue
                }
            }
            break
        }
        return current
    }

    private static func navigationStack(from root: UIViewController?) -> [String] {
        guard let root else { return [] }
        var names: [String] = []
        func walk(_ vc: UIViewController) {
            names.append(describe(vc))
            if let nav = vc as? UINavigationController {
                for child in nav.viewControllers {
                    walk(child)
                }
            } else if let tabs = vc as? UITabBarController, let selected = tabs.selectedViewController {
                walk(selected)
            } else if let split = vc as? UISplitViewController {
                for child in split.viewControllers {
                    walk(child)
                }
            } else {
                for child in vc.children {
                    walk(child)
                }
            }
        }
        walk(root)
        // Cap noise.
        if names.count > 32 {
            return Array(names.prefix(32))
        }
        return names
    }

    private static func presentedChain(from root: UIViewController?) -> [String] {
        var names: [String] = []
        var current = root
        while let vc = current {
            names.append(describe(vc))
            current = vc.presentedViewController
            if names.count >= 16 { break }
        }
        return names
    }

    private static func describe(_ vc: UIViewController?) -> String {
        guard let vc else { return "(nil)" }
        let typeName = String(describing: type(of: vc))
        if let title = vc.title, !title.isEmpty {
            return "\(typeName) (title: \(title))"
        }
        if let nav = vc as? UINavigationController {
            return "\(typeName) [\(nav.viewControllers.count) VCs]"
        }
        if let tabs = vc as? UITabBarController {
            return "\(typeName) [tab \(tabs.selectedIndex)]"
        }
        return typeName
    }

    private static func orientationLabel(_ orientation: UIDeviceOrientation) -> String {
        switch orientation {
        case .portrait: return "portrait"
        case .portraitUpsideDown: return "portraitUpsideDown"
        case .landscapeLeft: return "landscapeLeft"
        case .landscapeRight: return "landscapeRight"
        case .faceUp: return "faceUp"
        case .faceDown: return "faceDown"
        default: return "unknown"
        }
    }

    private static func isSimulator() -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private static func deviceModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }
}
#endif
