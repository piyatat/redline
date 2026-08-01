import Foundation
import RedlineShared

enum FeedbackBundleWriter {
    static func write(
        payload: FeedbackPayload,
        itemId: String,
        workspaceRoot: URL?,
        supportDirectory: URL
    ) throws -> URL {
        let screenSlug = sanitizePathComponent(payload.screen)
        let safeItemId = sanitizePathComponent(itemId)
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")

        let root = (workspaceRoot ?? supportDirectory.appendingPathComponent("feedback", isDirectory: true))
            .standardizedFileURL
        let bundleDir = root
            .appendingPathComponent(screenSlug, isDirectory: true)
            .appendingPathComponent("\(timestamp)-\(safeItemId)", isDirectory: true)
            .standardizedFileURL

        guard isPath(bundleDir, inside: root) else {
            throw FeedbackBundleWriterError.pathEscape(bundleDir.path)
        }

        try FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)

        let jsonURL = bundleDir.appendingPathComponent("feedback.json")
        try payload.encode().write(to: jsonURL)

        if let data = Data(base64Encoded: payload.compositePngBase64) {
            try data.write(to: bundleDir.appendingPathComponent("composite.png"))
        }

        let prompt = AgentPromptBuilder().makePrompt(for: payload, bundleDirectory: bundleDir)
        try prompt.data(using: .utf8)?.write(to: bundleDir.appendingPathComponent("prompt.md"))

        appendInboxMarkdown(payload: payload, bundleDir: bundleDir, workspaceRoot: root)

        return bundleDir
    }

    /// Allowlist for path segments — blocks `..`, separators, and empty.
    static func sanitizePathComponent(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var replaced = trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        while replaced.contains("..") {
            replaced = replaced.replacingOccurrences(of: "..", with: ".")
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let filtered = String(replaced.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        let collapsed = filtered
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        let candidate = collapsed.isEmpty ? "untitled" : String(collapsed.prefix(120))
        if candidate == "." || candidate == ".." {
            return "untitled"
        }
        return candidate
    }

    private static func isPath(_ child: URL, inside parent: URL) -> Bool {
        let c = child.path
        let p = parent.path
        if c == p { return true }
        let prefix = p.hasSuffix("/") ? p : p + "/"
        return c.hasPrefix(prefix)
    }

    private static func appendInboxMarkdown(payload: FeedbackPayload, bundleDir: URL, workspaceRoot: URL) {
        let inboxURL = workspaceRoot.appendingPathComponent("INBOX.md")
        let entry = """
        ## \(payload.screen) — \(payload.region)
        - **Captured:** \(payload.capturedTs)
        - **Comment:** \(payload.comment)
        - **Bundle:** `\(bundleDir.path)`

        """
        if FileManager.default.fileExists(atPath: inboxURL.path) {
            if let handle = try? FileHandle(forWritingTo: inboxURL) {
                handle.seekToEndOfFile()
                handle.write(entry.data(using: .utf8)!)
                try? handle.close()
            }
        } else {
            try? ("# Redline INBOX\n\n" + entry).data(using: .utf8)?.write(to: inboxURL)
        }
    }
}

enum FeedbackBundleWriterError: Error, LocalizedError {
    case pathEscape(String)

    var errorDescription: String? {
        switch self {
        case .pathEscape(let path): return "Refusing to write feedback outside workspace: \(path)"
        }
    }
}
