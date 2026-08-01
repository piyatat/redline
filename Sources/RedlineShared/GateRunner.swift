import Foundation

public struct GateManifest: Codable, Equatable, Sendable {
    public var version: Int
    public var stages: [GateStage]

    public init(version: Int = 1, stages: [GateStage]) {
        self.version = version
        self.stages = stages
    }
}

public struct GateStage: Codable, Equatable, Sendable {
    public var name: String
    public var script: String
    public var args: [String]
    public var required: Bool

    public init(name: String, script: String, args: [String] = [], required: Bool = true) {
        self.name = name
        self.script = script
        self.args = args
        self.required = required
    }
}

public struct GateRunResult: Equatable, Codable, Sendable {
    public var passed: Bool
    public var stages: [GateStageResult]

    public init(passed: Bool, stages: [GateStageResult]) {
        self.passed = passed
        self.stages = stages
    }
}

public struct GateStageResult: Equatable, Codable, Sendable {
    public var name: String
    public var exitCode: Int32
    public var output: String
    public var required: Bool

    public var succeeded: Bool { exitCode == 0 }
}

public enum GateRunner {
    public static let defaultManifest = GateManifest(stages: [
        GateStage(name: "validate-feedback", script: "scripts/validate-feedback.mjs"),
    ])

    public static func loadManifest(workspaceRoot: URL) -> GateManifest {
        if let envPath = ProcessInfo.processInfo.environment[RedlineEnvironment.gateManifestKey] {
            let url = URL(fileURLWithPath: envPath)
            if let data = try? Data(contentsOf: url),
               let manifest = try? JSONDecoder().decode(GateManifest.self, from: data) {
                return manifest
            }
        }

        let workspaceManifest = workspaceRoot.appendingPathComponent("scripts/gate-manifest.json")
        if let data = try? Data(contentsOf: workspaceManifest),
           let manifest = try? JSONDecoder().decode(GateManifest.self, from: data) {
            return manifest
        }

        if let bundled = bundledManifestURL(),
           let data = try? Data(contentsOf: bundled),
           let manifest = try? JSONDecoder().decode(GateManifest.self, from: data) {
            return manifest
        }

        return defaultManifest
    }

    public static func run(
        workspaceRoot: URL,
        bundleDirectory: URL? = nil,
        extraEnv: [String: String] = [:]
    ) -> GateRunResult {
        let manifest = loadManifest(workspaceRoot: workspaceRoot)
        var stageResults: [GateStageResult] = []
        var passed = true

        for stage in manifest.stages {
            let scriptURL = resolveScript(stage.script, workspaceRoot: workspaceRoot)
            guard FileManager.default.fileExists(atPath: scriptURL.path) else {
                let result = GateStageResult(
                    name: stage.name,
                    exitCode: stage.required ? 127 : 0,
                    output: stage.required ? "missing script: \(stage.script)" : "skipped (optional, not found)",
                    required: stage.required
                )
                stageResults.append(result)
                if stage.required { passed = false }
                continue
            }

            var env = ProcessInfo.processInfo.environment
            env[RedlineEnvironment.workspaceRootKey] = workspaceRoot.path
            if let bundleDirectory {
                env["REDLINE_BUNDLE_DIR"] = bundleDirectory.path
            }
            for (key, value) in extraEnv {
                env[key] = value
            }

            let result = runScript(scriptURL, args: stage.args, cwd: workspaceRoot, env: env)
            let stageResult = GateStageResult(
                name: stage.name,
                exitCode: result.exitCode,
                output: result.output,
                required: stage.required
            )
            stageResults.append(stageResult)
            if stage.required && result.exitCode != 0 {
                passed = false
            }
        }

        return GateRunResult(passed: passed, stages: stageResults)
    }

    private static func resolveScript(_ path: String, workspaceRoot: URL) -> URL {
        let root = workspaceRoot.resolvingSymlinksInPath().standardizedFileURL
        let candidate: URL
        if path.hasPrefix("/") {
            candidate = URL(fileURLWithPath: path)
        } else {
            candidate = root.appendingPathComponent(path)
        }
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        let c = resolved.path
        let p = root.path
        let prefix = p.hasSuffix("/") ? p : p + "/"
        guard c == p || c.hasPrefix(prefix) else {
            return root.appendingPathComponent(".__redline_blocked_script__")
        }
        return resolved
    }

    private static func bundledManifestURL() -> URL? {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidate = cwd.appendingPathComponent("scripts/gate-manifest.json")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        return nil
    }

    private static func runScript(
        _ script: URL,
        args: [String],
        cwd: URL,
        env: [String: String]
    ) -> (exitCode: Int32, output: String) {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        if script.pathExtension == "mjs" || script.pathExtension == "js" {
            process.arguments = ["node", script.path] + args
        } else if script.pathExtension == "sh" {
            process.arguments = ["bash", script.path] + args
        } else {
            process.arguments = [script.path] + args
        }
        process.currentDirectoryURL = cwd
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch {
            return (127, error.localizedDescription)
        }
        #else
        _ = script
        _ = args
        _ = cwd
        _ = env
        return (127, "GateRunner subprocesses are only supported on macOS")
        #endif
    }
}
