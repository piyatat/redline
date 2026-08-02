import Foundation
import RedlineShared

enum RedlineCLI {
    static func main() {
        var args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            printUsage()
            exit(1)
        }
        args.removeFirst()

        do {
            switch command {
            case "health":
                let ok = try RedlineHTTPClient().health()
                print(ok ? "ok" : "down")
            case "inbox":
                try runInbox(args)
            case "agent":
                try runAgent(args)
            case "inspect":
                try runInspect(args)
            case "gates":
                try runGates(args)
            case "mcp":
                MCPStdioServer().run()
            case "cursor":
                try runCursor(args)
            default:
                printUsage()
                exit(1)
            }
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func workspaceRoot(from args: [String]) -> URL {
        if let idx = args.firstIndex(of: "--workspace"), idx + 1 < args.count {
            return URL(fileURLWithPath: args[idx + 1])
        }
        if let env = ProcessInfo.processInfo.environment[RedlineEnvironment.workspaceRootKey] {
            return URL(fileURLWithPath: env)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private static func bundleDirectory(from args: [String]) -> URL? {
        if let idx = args.firstIndex(of: "--bundle"), idx + 1 < args.count {
            return URL(fileURLWithPath: args[idx + 1])
        }
        return nil
    }

    private static func inboxItem(id: String) throws -> InboxItem {
        let items = try RedlineHTTPClient().inboxList()
        guard let item = items.first(where: { $0.id == id }) else {
            throw RedlineHTTPError.badStatus(404)
        }
        return item
    }

    private static func runGates(_ args: [String]) throws {
        guard args.first == "run" else {
            print("usage: redline gates run [--workspace PATH] [--bundle PATH]")
            exit(1)
        }
        let workspace = workspaceRoot(from: args)
        let bundle = bundleDirectory(from: args)
        let result = GateRunner.run(workspaceRoot: workspace, bundleDirectory: bundle)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(data: try encoder.encode(result.stages), encoding: .utf8) ?? "[]")
        if !result.passed { exit(2) }
    }

    private static func runInbox(_ args: [String]) throws {
        guard let sub = args.first else {
            print("usage: redline inbox list|show <id>|set-status <id> <status> [summary]")
            exit(1)
        }
        let client = RedlineHTTPClient()
        switch sub {
        case "list":
            let items = try client.inboxList()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            print(String(data: data, encoding: .utf8) ?? "[]")
        case "show":
            guard let id = args.dropFirst().first else {
                print("usage: redline inbox show <id>")
                exit(1)
            }
            let item = try inboxItem(id: id)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            print(String(data: try encoder.encode(item), encoding: .utf8) ?? "{}")
        case "set-status":
            let rest = Array(args.dropFirst())
            guard rest.count >= 2 else {
                print("usage: redline inbox set-status <id> <pending|agent_running|applied|failed> [summary]")
                exit(1)
            }
            let id = rest[0]
            let status = rest[1]
            let summary = rest.count > 2 ? rest.dropFirst(2).joined(separator: " ") : nil
            let item = try client.inboxSetStatus(id: id, status: status, summary: summary)
            print("ok \(item.id) → \(item.status.rawValue)")
        default:
            print("usage: redline inbox list|show <id>|set-status <id> <status> [summary]")
            exit(1)
        }
    }

    private static func runAgent(_ args: [String]) throws {
        guard args.first == "run", let id = args.dropFirst().first else {
            print("usage: redline agent run <inbox-id>")
            exit(1)
        }
        let item = try inboxItem(id: id)
        guard let bundle = item.bundleDirectory else {
            throw RedlineHTTPError.badStatus(404)
        }
        let hook = ProcessInfo.processInfo.environment[RedlineEnvironment.agentHookKey]
        guard let hook, !hook.isEmpty else {
            print("Set \(RedlineEnvironment.agentHookKey) to run agent hook")
            exit(1)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: hook)
        process.arguments = [id, bundle]
        try process.run()
        process.waitUntilExit()
        exit(process.terminationStatus == 0 ? 0 : 2)
    }

    private static func runInspect(_ args: [String]) throws {
        guard args.first == "ping" else {
            print("usage: redline inspect ping [--port N]")
            exit(1)
        }
        var port = UInt16(RedlinePorts.simulatorInspectStart)
        if let idx = args.firstIndex(of: "--port"), idx + 1 < args.count, let value = UInt16(args[idx + 1]) {
            port = value
        }
        let client = InspectorClient()
        let sem = DispatchSemaphore(value: 0)
        var appInfo: InspectableAppInfo?
        var inspectError: Error?
        Task {
            do {
                appInfo = try await client.ping(port: port)
            } catch {
                inspectError = error
            }
            sem.signal()
        }
        sem.wait()
        if let inspectError { throw inspectError }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(data: try encoder.encode(appInfo!), encoding: .utf8) ?? "{}")
    }

    private static func runCursor(_ args: [String]) throws {
        guard let sub = args.first else {
            print("usage: redline cursor setup --project PATH [--package PATH] [--print-deeplink]")
            exit(1)
        }
        switch sub {
        case "setup":
            let project = flagValue("--project", in: args)
                ?? FileManager.default.currentDirectoryPath
            let package = flagValue("--package", in: args)
                ?? CursorDesktopIntegration.resolvePackagePath()
            guard let package else {
                throw CursorDesktopError.missingPackage
            }
            let result = try CursorDesktopIntegration.installIntoProject(
                projectPath: project,
                packagePath: package,
                workspaceRoot: project
            )
            print("mcp: \(result.mcpJSONPath)")
            print("skill: \(result.skillPath)")
            print("command: \(result.commandPath)")
            if args.contains("--print-deeplink") {
                print("deeplink: \(result.deeplink)")
            }
            if args.contains("--open") {
                #if os(macOS)
                if let url = URL(string: result.deeplink) {
                    // Prefer `open` so we don't need AppKit in the CLI target.
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                    process.arguments = [url.absoluteString]
                    try process.run()
                    process.waitUntilExit()
                }
                #endif
            }
        default:
            print("usage: redline cursor setup --project PATH [--package PATH] [--print-deeplink] [--open]")
            exit(1)
        }
    }

    private static func flagValue(_ name: String, in args: [String]) -> String? {
        guard let idx = args.firstIndex(of: name), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }

    private static func printUsage() {
        print("""
        redline — CLI for Redline Mac receiver (inbox / agents / MCP)

        Commands:
          health
          inbox list | inbox show <id> | inbox set-status <id> <status> [summary]
          agent run <id>
          inspect ping [--port N]   # optional iOS hierarchy TCP
          gates run [--workspace PATH] [--bundle PATH]
          cursor setup --project PATH [--package PATH] [--print-deeplink] [--open]
          mcp
        """)
    }
}
