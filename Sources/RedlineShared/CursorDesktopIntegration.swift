import Foundation

/// Install / configure Redline MCP + wait skill for Cursor desktop (desktop MCP plugins work there).
public enum CursorDesktopIntegration {
    public static let serverName = "redline"

    public struct MCPServerConfig: Equatable, Sendable {
        public var command: String
        public var args: [String]
        public var env: [String: String]

        public init(command: String, args: [String], env: [String: String] = [:]) {
            self.command = command
            self.args = args
            self.env = env
        }
    }

    public struct InstallResult: Equatable, Sendable {
        public var mcpJSONPath: String
        public var skillPath: String
        public var commandPath: String
        public var deeplink: String
    }

    /// Absolute path to the Redline SPM checkout (`Package.swift` with product `redline`).
    public static func resolvePackagePath(explicit: String? = nil) -> String? {
        if let explicit {
            let trimmed = explicit.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, isRedlinePackage(at: trimmed) { return trimmed }
        }
        if let env = ProcessInfo.processInfo.environment["REDLINE_PACKAGE_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty,
           isRedlinePackage(at: env) {
            return env
        }
        // Walk up from this source file (works with local SPM checkouts).
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0 ..< 8 {
            if isRedlinePackage(at: url.path) { return url.path }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return nil
    }

    public static func isRedlinePackage(at path: String) -> Bool {
        let root = URL(fileURLWithPath: path)
        let manifest = root.appendingPathComponent("Package.swift")
        guard FileManager.default.fileExists(atPath: manifest.path),
              let text = try? String(contentsOf: manifest, encoding: .utf8) else {
            return false
        }
        return text.contains("name: \"Redline\"") || text.contains("name: \"redline\"")
            || text.contains(".executable(name: \"redline\"")
    }

    public static func makeServerConfig(
        packagePath: String,
        workspaceRoot: String? = nil,
        apiToken: String? = nil,
        includeAPITokenInEnv: Bool = false
    ) -> MCPServerConfig {
        var env: [String: String] = [
            // Cursor’s MCP host often has a minimal PATH; Xcode tools need these.
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:/Applications/Xcode.app/Contents/Developer/usr/bin:\(NSHomeDirectory())/.local/bin",
            "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer",
        ]
        if let workspaceRoot, !workspaceRoot.isEmpty {
            env[RedlineEnvironment.workspaceRootKey] = workspaceRoot
        }
        // Never embed tokens in project mcp.json by default (easy to commit).
        if includeAPITokenInEnv, let apiToken, !apiToken.isEmpty {
            env[RedlineEnvironment.apiTokenKey] = apiToken
        }

        let debugBinary = URL(fileURLWithPath: packagePath)
            .appendingPathComponent(".build/debug/redline")
            .path
        let releaseBinary = URL(fileURLWithPath: packagePath)
            .appendingPathComponent(".build/release/redline")
            .path
        if FileManager.default.isExecutableFile(atPath: debugBinary) {
            return MCPServerConfig(command: debugBinary, args: ["mcp"], env: env)
        }
        if FileManager.default.isExecutableFile(atPath: releaseBinary) {
            return MCPServerConfig(command: releaseBinary, args: ["mcp"], env: env)
        }

        let swift = "/usr/bin/swift"
        return MCPServerConfig(
            command: FileManager.default.isExecutableFile(atPath: swift) ? swift : "swift",
            args: ["run", "--package-path", packagePath, "redline", "mcp"],
            env: env
        )
    }

    /// Config object encoded into the Cursor MCP install deeplink (`name` is separate).
    public static func deeplinkConfigJSON(for config: MCPServerConfig) throws -> Data {
        var object: [String: Any] = [
            "command": config.command,
            "args": config.args,
        ]
        if !config.env.isEmpty {
            object["env"] = config.env
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        // Foundation escapes `/` as `\/`; Cursor expects normal paths in the install config.
        guard var text = String(data: data, encoding: .utf8) else { return data }
        text = text.replacingOccurrences(of: "\\/", with: "/")
        return Data(text.utf8)
    }

    public static func installDeeplink(for config: MCPServerConfig) throws -> URL {
        let json = try deeplinkConfigJSON(for: config)
        let b64 = json.base64EncodedString()
        let name = serverName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? serverName
        let urlString = "cursor://anysphere.cursor-deeplink/mcp/install?name=\(name)&config=\(b64)"
        guard let url = URL(string: urlString) else {
            throw CursorDesktopError.invalidDeeplink
        }
        return url
    }

    /// Merge `redline` into `<project>/.cursor/mcp.json` and write skill + slash command.
    @discardableResult
    public static func installIntoProject(
        projectPath: String,
        packagePath: String,
        workspaceRoot: String? = nil,
        apiToken: String? = nil
    ) throws -> InstallResult {
        let project = projectPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !project.isEmpty, FileManager.default.fileExists(atPath: project) else {
            throw CursorDesktopError.missingProject
        }
        guard isRedlinePackage(at: packagePath) else {
            throw CursorDesktopError.missingPackage
        }

        let config = makeServerConfig(
            packagePath: packagePath,
            workspaceRoot: workspaceRoot ?? project,
            apiToken: nil,
            includeAPITokenInEnv: false
        )
        let cursorDir = URL(fileURLWithPath: project).appendingPathComponent(".cursor", isDirectory: true)
        try FileManager.default.createDirectory(at: cursorDir, withIntermediateDirectories: true)

        let mcpURL = cursorDir.appendingPathComponent("mcp.json")
        try writeMergedMCPJSON(at: mcpURL, config: config)

        let skillDir = cursorDir
            .appendingPathComponent("skills", isDirectory: true)
            .appendingPathComponent("redline-wait", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let skillURL = skillDir.appendingPathComponent("SKILL.md")
        try skillMarkdown.data(using: .utf8)?.write(to: skillURL, options: .atomic)

        let commandsDir = cursorDir.appendingPathComponent("commands", isDirectory: true)
        try FileManager.default.createDirectory(at: commandsDir, withIntermediateDirectories: true)
        let commandURL = commandsDir.appendingPathComponent("redline-wait.md")
        try commandMarkdown.data(using: .utf8)?.write(to: commandURL, options: .atomic)

        try ensureProjectGitignore(at: project)

        let deeplink = try installDeeplink(for: config).absoluteString
        return InstallResult(
            mcpJSONPath: mcpURL.path,
            skillPath: skillURL.path,
            commandPath: commandURL.path,
            deeplink: deeplink
        )
    }

    /// Append Redline ignore entries to the project `.gitignore` when missing.
    public static func ensureProjectGitignore(at projectPath: String) throws {
        let url = URL(fileURLWithPath: projectPath).appendingPathComponent(".gitignore")
        let entries = [
            FeedbackBundleStager.folderName + "/",
            ".cursor/mcp.json",
        ]
        var existing = ""
        if FileManager.default.fileExists(atPath: url.path) {
            existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        var additions: [String] = []
        for entry in entries where !existing.contains(entry) {
            additions.append(entry)
        }
        guard !additions.isEmpty else { return }
        let block = (existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n")
            + "\n# Redline\n"
            + additions.joined(separator: "\n")
            + "\n"
        if existing.isEmpty {
            try block.write(to: url, atomically: true, encoding: .utf8)
        } else {
            try (existing + block).write(to: url, atomically: true, encoding: .utf8)
        }
    }

    public static func writeMergedMCPJSON(at url: URL, config: MCPServerConfig) throws {
        var root: [String: Any] = ["mcpServers": [String: Any]()]
        if FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = existing
        }
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        var entry: [String: Any] = [
            "command": config.command,
            "args": config.args,
        ]
        if !config.env.isEmpty {
            entry["env"] = config.env
        }
        servers[serverName] = entry
        root["mcpServers"] = servers
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        guard var text = String(data: out, encoding: .utf8) else {
            try out.write(to: url, options: .atomic)
            return
        }
        text = text.replacingOccurrences(of: "\\/", with: "/")
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    // MARK: - Templates

    public static let skillMarkdown = """
    ---
    name: redline-wait
    description: >-
      Wait for the next Redline designer feedback via MCP tool redline_wait_for_feedback,
      then inspect the inbox item and apply UI/spec fixes in the project. Use when the user
      asks to wait for redline feedback, poll Redline, or process a designer markup from
      the Mac inbox while staying in Cursor desktop (desktop MCP plugins available).
    ---

    # Redline — wait for feedback

    ## Prerequisites

    - **Redline.app** is running (receiver on `:8765`).
    - Settings → **When feedback arrives** = **Cursor desktop (MCP)** so Agent CLI is not auto-started.
    - Redline MCP server `redline` is enabled (project `.cursor/mcp.json` or Cursor Settings → MCP).
    - Designer will Save a redline from the iOS app (or use Mac Inbox).

    ## Steps

    1. Call MCP tool **`redline_wait_for_feedback`** with `timeoutSeconds`: `"300"` (default is 300).
       - Do **not** treat an already-present inbox item as new; the tool waits for a new id.
       - On success the Mac Inbox item is marked **Running** (`agent_running`).
    2. When it returns, note `id`, `screen`, `region`, `comment`, `spec`, `runtime`, and `bundleDirectory`.
       - Composite PNG is omitted from MCP JSON (`compositeOmitted: true`) — read the image from disk.
    3. Optionally call **`redline_inbox_show`** with that `id` if you need details again.
    4. Read staged feedback assets (preferred):
       - `.redline-feedback/prompt.md`
       - `.redline-feedback/composite.png`
       - fallback: absolute paths under `bundleDirectory`
    5. Implement the designer request in this repo (use other MCP tools if needed).
    6. Call **`redline_inbox_set_status`** with the same `id`:
       - `status`: `"applied"` when done (alias `"finished"`), or `"failed"` if blocked
       - `summary`: short note of what changed (shown in Redline Inbox)
    7. Summarize what changed and which screen/region it addressed.

    ## Notes

    - Prefer this desktop Agent path when desktop MCP plugins are required — headless CLI may not expose them.
    - Always update inbox status when you finish (or fail) so designers see progress in Redline.app.
    - If the MCP tool is missing, tell the user to run Redline.app → Settings → **Install into project** / **Open MCP install in Cursor**.
    - Set `REDLINE_API_TOKEN` in the shell / Cursor MCP env if the Mac receiver requires a token — do not commit tokens into `.cursor/mcp.json`.
    """

    public static let commandMarkdown = """
    ---
    description: Wait for the next Redline designer feedback (MCP redline_wait_for_feedback), then fix the UI/spec.
    ---

    Wait for new Redline designer feedback and act on it.

    Prerequisites: Redline.app running; Settings → When feedback arrives = **Cursor desktop (MCP)**.

    1. Ensure the `redline` MCP server is available.
    2. Call **`redline_wait_for_feedback`** with `timeoutSeconds` = `300`.
    3. When feedback arrives, read `.redline-feedback/prompt.md` and `.redline-feedback/composite.png` (PNG is not in the MCP JSON).
    4. Apply the requested change in this project. Use other MCP tools if needed.
    5. Call **`redline_inbox_set_status`** with `id` from step 2, `status` = `applied` (or `failed`), and a short `summary`.
    6. Report what you changed.

    If `redline_wait_for_feedback` is unavailable, tell me to install Redline MCP from Redline.app Settings or `.cursor/mcp.json`.
    """
}

public enum CursorDesktopError: Error, LocalizedError {
    case missingProject
    case missingPackage
    case invalidDeeplink
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingProject: return "Set Project folder to the repo Cursor should edit"
        case .missingPackage: return "Set Redline package path to this repo’s Package.swift checkout"
        case .invalidDeeplink: return "Could not build Cursor MCP install link"
        case .writeFailed(let message): return message
        }
    }
}
