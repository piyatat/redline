import Foundation

/// Invokes Claude Code CLI headlessly against a project directory.
enum ClaudeCLIAgent {
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
        /// Extra directory the agent may read (feedback bundle with prompt.md / composite.png).
        var bundleDirectory: String?
        var claudeAgentPath: String?
        var timeout: TimeInterval
        var continueSession: Bool
        var controller: AgentProcessController?
        var onOutput: (@Sendable (String) -> Void)?
    }

    static func resolveBinary(override: String?) -> String? {
        if let override, !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url.path
            }
        }

        if let claude = which("claude") {
            return claude
        }

        let candidates = [
            "\(NSHomeDirectory())/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
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

    static let installCommand = "npm install -g @anthropic-ai/claude-code"
    static let authHint = "Then run `claude` to sign in, or set ANTHROPIC_API_KEY."
    static let docsURL = URL(string: "https://docs.anthropic.com/en/docs/claude-code")

    static func installStatus(override: String?) -> InstallStatus {
        if let path = resolveBinary(override: override) {
            return InstallStatus(
                isInstalled: true,
                pathLabel: path,
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
        return "Not found — install: \(installCommand)"
    }

    static func run(_ invocation: Invocation) async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runSync(invocation))
            }
        }
    }

    private static func runSync(_ invocation: Invocation) -> Result {
        guard let binary = resolveBinary(override: invocation.claudeAgentPath) else {
            let hint = "Install: npm install -g @anthropic-ai/claude-code\nOr set Settings → Claude agent path.\nAuth: `claude` login or ANTHROPIC_API_KEY."
            invocation.onOutput?(hint + "\n")
            return Result(
                success: false,
                message: "Claude Code CLI not found",
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
                resolvedBinary: binary,
                cancelled: false
            )
        }

        var args = [
            "-p",
            "--output-format", "stream-json",
            "--permission-mode", "acceptEdits",
        ]
        if invocation.continueSession {
            args.append("--continue")
        }
        if let bundle = invocation.bundleDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bundle.isEmpty,
           FileManager.default.fileExists(atPath: bundle) {
            args.append(contentsOf: ["--add-dir", bundle])
        }
        args.append(invocation.prompt)

        invocation.onOutput?("Launching \(binary) (stream-json)…\n")
        invocation.onOutput?("cwd: \(project)\n\n")

        let streamed = ProcessStreamer.run(
            executable: URL(fileURLWithPath: binary),
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
                : (streamed.success ? "Claude Code exit 0" : "Claude Code exit \(streamed.exitCode)"),
            output: streamed.output,
            resolvedBinary: binary,
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
