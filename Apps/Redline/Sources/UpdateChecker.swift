import AppKit
import Foundation
import RedlineShared

struct UpdateChecker {
    struct UpdateInfo: Equatable {
        var version: String
        var downloadURL: URL
        var notes: String?
    }

    enum CheckResult: Equatable {
        case notConfigured
        case upToDate(current: String)
        case available(UpdateInfo)
        case failed(String)
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Only honors an explicit `REDLINE_APPCAST_URL` — never a hard-coded example host.
    static var appcastURL: URL? {
        guard let raw = ProcessInfo.processInfo.environment[RedlineEnvironment.appcastURLKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http"
        else {
            return nil
        }
        return url
    }

    static func checkForUpdates() async -> CheckResult {
        guard let appcastURL else { return .notConfigured }
        do {
            let (data, response) = try await URLSession.shared.data(from: appcastURL)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return .failed("Appcast returned HTTP \(http.statusCode)")
            }
            guard let xml = String(data: data, encoding: .utf8),
                  let info = parseAppcast(xml) else {
                return .failed("Could not parse appcast feed")
            }
            if isRemoteVersionNewer(info.version, than: currentVersion) {
                return .available(info)
            }
            return .upToDate(current: currentVersion)
        } catch {
            fputs("Update check failed: \(error)\n", stderr)
            return .failed(error.localizedDescription)
        }
    }

    /// Menu / toolbar entry point — shows a modal alert on the main actor.
    @MainActor
    static func presentCheckFromMenu() async {
        let result = await checkForUpdates()
        switch result {
        case .notConfigured:
            presentAlert(
                title: "Updates Not Configured",
                message: "Set REDLINE_APPCAST_URL to an HTTPS appcast feed before checking. See docs/appcast-setup.md."
            )
        case .upToDate(let current):
            presentAlert(
                title: "You’re Up to Date",
                message: "Redline \(current) is the latest version from the configured appcast."
            )
        case .available(let info):
            let notes = info.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = (notes?.isEmpty == false)
                ? "Version \(info.version) is available.\n\n\(notes!)"
                : "Version \(info.version) is available."
            let alert = NSAlert()
            alert.messageText = "Update Available"
            alert.informativeText = detail
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open Download")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(info.downloadURL)
            }
        case .failed(let message):
            presentAlert(title: "Update Check Failed", message: message)
        }
    }

    @MainActor
    private static func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Loose dotted numeric compare (`1.2` < `1.10`); non-numeric tails fall back to string compare.
    static func isRemoteVersionNewer(_ remote: String, than local: String) -> Bool {
        let r = versionParts(remote)
        let l = versionParts(local)
        let count = max(r.count, l.count)
        for i in 0..<count {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }

    private static func versionParts(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
    }

    private static func parseAppcast(_ xml: String) -> UpdateInfo? {
        let version = firstMatch(in: xml, pattern: "<shortVersionString>([^<]+)</shortVersionString>")
            ?? firstMatch(in: xml, pattern: "<sparkle:shortVersionString>([^<]+)</sparkle:shortVersionString>")
            ?? firstMatch(in: xml, pattern: "shortVersionString=\"([^\"]+)\"")
        guard let version,
              let enclosure = firstMatch(in: xml, pattern: "url=\"([^\"]+)\""),
              let url = URL(string: enclosure) else {
            return nil
        }
        let notes = firstMatch(in: xml, pattern: "<description><!\\[CDATA\\[([\\s\\S]*?)\\]\\]></description>")
        return UpdateInfo(version: version, downloadURL: url, notes: notes)
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }
}
