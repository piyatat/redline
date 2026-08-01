import Foundation
import RedlineShared

struct UpdateChecker {
    struct UpdateInfo: Equatable {
        var version: String
        var downloadURL: URL
        var notes: String?
    }

    static var appcastURL: URL? {
        if let raw = ProcessInfo.processInfo.environment[RedlineEnvironment.appcastURLKey],
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://example.com/redline/appcast.xml")
    }

    static func checkForUpdates() async -> UpdateInfo? {
        guard let appcastURL else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: appcastURL)
            guard let xml = String(data: data, encoding: .utf8) else { return nil }
            return parseAppcast(xml)
        } catch {
            fputs("Update check failed: \(error)\n", stderr)
            return nil
        }
    }

    private static func parseAppcast(_ xml: String) -> UpdateInfo? {
        let version = firstMatch(in: xml, pattern: "<shortVersionString>([^<]+)</shortVersionString>")
            ?? firstMatch(in: xml, pattern: "<sparkle:shortVersionString>([^<]+)</sparkle:shortVersionString>")
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
