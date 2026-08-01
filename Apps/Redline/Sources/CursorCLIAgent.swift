import Foundation

/// Invokes Cursor Agent CLI headlessly against a project directory.
enum CursorCLIAgent {
    struct Result: Sendable {
        var success: Bool
        var message: String
        var output: String
        var resolvedBinary: String?
        var cancelled: Bool
    }

    struct Invocation: Sendable {
        var projectPath: String
        var prompt: String
        var cursorAgentPath: String?
        var timeout: TimeInterval
        var continueSession: Bool
        var controller: AgentProcessController?
        var onOutput: (@Sendable (String) -> Void)?
    }

    /// Prefer explicit path, then `agent`, then `cursor` (with `agent` subcommand).
    static func resolveBinary(override: String?) -> (path: String, usesAgentSubcommand: Bool)? {
        if let override, !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                let name = url.lastPathComponent.lowercased()
                return (url.path, name == "cursor")
            }
        }

        if let agent = which("agent") {
            return (agent, false)
        }
        if let cursor = which("cursor") {
            return (cursor, true)
        }
        let candidates = [
            ("\(NSHomeDirectory())/.local/bin/agent", false),
            ("/usr/local/bin/agent", false),
            ("/opt/homebrew/bin/agent", false),
            ("/usr/local/bin/cursor", true),
            ("/opt/homebrew/bin/cursor", true),
        ]
        for (path, sub) in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return (path, sub)
            }
        }
        return nil
    }

    struct InstallStatus: Sendable {
        var isInstalled: Bool
        var pathLabel: String?
        var installCommand: String
        var authHint: String
        var docsURL: URL?

        var summary: String {
            if isInstalled, let pathLabel {
                return "Installed — \(pathLabel)"
            }
            return "Not installed"
        }
    }

    static let installCommand = "curl https://cursor.com/install -fsS | bash"
    static let authHint = "Then run `agent login`, or set CURSOR_API_KEY."
    static let docsURL = URL(string: "https://cursor.com/docs/cli/overview")

    static func installStatus(override: String?) -> InstallStatus {
        if let resolved = resolveBinary(override: override) {
            let mode = resolved.usesAgentSubcommand ? " (via `cursor agent`)" : ""
            return InstallStatus(
                isInstalled: true,
                pathLabel: "\(resolved.path)\(mode)",
                installCommand: installCommand,
                authHint: authHint,
                docsURL: docsURL
            )
        }
        return InstallStatus(
            isInstalled: false,
            pathLabel: nil,
            installCommand: installCommand,
            authHint: authHint,
            docsURL: docsURL
        )
    }

    static func statusDescription(override: String?) -> String {
        let status = installStatus(override: override)
        if status.isInstalled, let path = status.pathLabel {
            return "Found: \(path)"
        }
        return "Not found — install with: \(installCommand)"
    }

    static func run(_ invocation: Invocation) async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runSync(invocation))
            }
        }
    }

    private static func runSync(_ invocation: Invocation) -> Result {
        guard let resolved = resolveBinary(override: invocation.cursorAgentPath) else {
            let hint = "Install: curl https://cursor.com/install -fsS | bash\nOr set Settings → Cursor agent path."
            invocation.onOutput?(hint + "\n")
            return Result(
                success: false,
                message: "Cursor Agent CLI not found",
                output: hint,
                resolvedBinary: nil,
                cancelled: false
            )
        }

        let project = invocation.projectPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !project.isEmpty, FileManager.default.fileExists(atPath: project) else {
            let hint = "Set Settings → Project folder to the repo the agent should edit."
            invocation.onOutput?(hint + "\n")
            return Result(
                success: false,
                message: "Project folder missing",
                output: hint,
                resolvedBinary: resolved.path,
                cancelled: false
            )
        }

        var args: [String] = []
        if resolved.usesAgentSubcommand {
            args.append("agent")
        }
        args.append(contentsOf: [
            "-p",
            "--force",
            "--output-format", "stream-json",
            "--stream-partial-output",
        ])
        if invocation.continueSession {
            args.append("--continue")
        }
        args.append(invocation.prompt)

        invocation.onOutput?("Launching \(resolved.path) (stream-json)…\n")
        invocation.onOutput?("cwd: \(project)\n\n")

        let streamed = ProcessStreamer.run(
            executable: URL(fileURLWithPath: resolved.path),
            arguments: args,
            currentDirectory: URL(fileURLWithPath: project),
            environment: ProcessStreamer.enrichedPATH(from: ProcessInfo.processInfo.environment),
            timeout: invocation.timeout,
            controller: invocation.controller,
            onOutput: invocation.onOutput
        )

        return Result(
            success: streamed.success,
            message: streamed.cancelled
                ? "stopped by user"
                : (streamed.success ? "Cursor agent exit 0" : "Cursor agent exit \(streamed.exitCode)"),
            output: streamed.output,
            resolvedBinary: resolved.path,
            cancelled: streamed.cancelled
        )
    }

    private static func which(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.environment = ProcessStreamer.enrichedPATH(from: ProcessInfo.processInfo.environment)
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let path, !path.isEmpty else { return nil }
            return path
        } catch {
            return nil
        }
    }
}
