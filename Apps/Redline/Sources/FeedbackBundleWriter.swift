import Foundation
import RedlineShared

enum FeedbackBundleWriter {
    static func write(
        payload: FeedbackPayload,
        itemId: String,
        workspaceRoot: URL?,
        supportDirectory: URL
    ) throws -> URL {
        let screenSlug = payload.screen.replacingOccurrences(of: "/", with: "-")
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")

        let root = workspaceRoot ?? supportDirectory.appendingPathComponent("feedback", isDirectory: true)
        let bundleDir = root
            .appendingPathComponent(screenSlug, isDirectory: true)
            .appendingPathComponent("\(timestamp)-\(itemId)", isDirectory: true)

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
