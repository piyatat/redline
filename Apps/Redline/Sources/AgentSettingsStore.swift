import Combine
import Foundation
import RedlineShared

@MainActor
final class AgentSettingsStore: ObservableObject {
    @Published var settings: AgentSettings

    /// `~/Library/Application Support/Redline`
    let supportDirectory: URL
    private let configURL: URL
    private var saveTask: Task<Void, Never>?
    private var persistCancellable: AnyCancellable?

    /// Default hook path under Application Support.
    var defaultHookPath: String {
        supportDirectory
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("redline-agent-hook.sh")
            .path
    }

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Redline", isDirectory: true)
        supportDirectory = dir
        configURL = dir.appendingPathComponent("config.json")

        Self.ensureSupportLayout(at: dir)

        // Always refresh the default hook script so behavior upgrades ship to existing installs.
        Self.installDefaultHook(at: dir, force: true)

        if let data = try? Data(contentsOf: configURL),
           let decoded = try? JSONDecoder().decode(AgentSettings.self, from: data) {
            settings = Self.withDefaultsFilled(decoded, supportDirectory: dir)
            if settings.hookPath != decoded.hookPath {
                persistToDisk()
            }
        } else {
            settings = Self.settingsFromEnvironment(supportDirectory: dir)
            persistToDisk()
        }

        // Debounced disk writes — avoid blocking UI / re-entrant publishes on every click.
        persistCancellable = $settings
            .dropFirst()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.persistToDisk()
            }
    }

    /// Immediate persist (directory pickers, install, etc.).
    func save() {
        saveTask?.cancel()
        var next = Self.withDefaultsFilled(settings, supportDirectory: supportDirectory)
        next.workspaceRoot = nil
        if next != settings {
            settings = next
        }
        persistToDisk(values: next)
    }

    /// Mutate settings in memory; disk write is debounced.
    func update(_ mutate: (inout AgentSettings) -> Void) {
        var next = settings
        mutate(&next)
        next.workspaceRoot = nil
        guard next != settings else { return }
        settings = next
    }

    private func persistToDisk(values: AgentSettings? = nil) {
        var next = values ?? settings
        next = Self.withDefaultsFilled(next, supportDirectory: supportDirectory)
        next.workspaceRoot = nil
        let url = configURL
        guard let data = try? JSONEncoder().encode(next) else { return }
        // Avoid main-thread filesystem stalls while clicking through Settings.
        saveTask?.cancel()
        saveTask = Task.detached(priority: .utility) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func resetHookToDefault() {
        settings.hookPath = defaultHookPath
        Self.ensureSupportLayout(at: supportDirectory)
        save()
    }

    var resolvedHookPath: String {
        let trimmed = settings.hookPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty { return trimmed }
        return defaultHookPath
    }

    /// Optional repo root for gate CLI (`REDLINE_WORKSPACE_ROOT`).
    static var gatesWorkspaceURL: URL? {
        guard let root = ProcessInfo.processInfo.environment[RedlineEnvironment.workspaceRootKey],
              !root.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: root)
    }

    // MARK: - Defaults

    private static func settingsFromEnvironment(supportDirectory: URL) -> AgentSettings {
        var settings = withDefaultsFilled(AgentSettings.defaults, supportDirectory: supportDirectory)
        if let raw = ProcessInfo.processInfo.environment[RedlineEnvironment.onNewFeedbackKey] {
            settings.onNewFeedback = AgentTriggerMode.fromPersisted(raw)
        }
        if let hook = ProcessInfo.processInfo.environment[RedlineEnvironment.agentHookKey], !hook.isEmpty {
            settings.hookPath = hook
        }
        settings.workspaceRoot = nil
        return settings
    }

    private static func withDefaultsFilled(_ settings: AgentSettings, supportDirectory: URL) -> AgentSettings {
        var next = settings
        let hook = supportDirectory
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("redline-agent-hook.sh")
            .path
        if next.hookPath == nil || next.hookPath?.isEmpty == true {
            next.hookPath = hook
        }
        // Bundles stay under Application Support; projectPath is for Cursor CLI cwd only.
        next.workspaceRoot = nil
        return next
    }

    private static func ensureSupportLayout(at supportDirectory: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: supportDirectory, withIntermediateDirectories: true)

        let bin = supportDirectory.appendingPathComponent("bin", isDirectory: true)
        try? fm.createDirectory(at: bin, withIntermediateDirectories: true)
        installDefaultHook(at: supportDirectory, force: false)

        let feedback = supportDirectory.appendingPathComponent("feedback", isDirectory: true)
        try? fm.createDirectory(at: feedback, withIntermediateDirectories: true)
    }

    private static func installDefaultHook(at supportDirectory: URL, force: Bool) {
        let fm = FileManager.default
        let bin = supportDirectory.appendingPathComponent("bin", isDirectory: true)
        try? fm.createDirectory(at: bin, withIntermediateDirectories: true)
        let hook = bin.appendingPathComponent("redline-agent-hook.sh")
        if force || !fm.fileExists(atPath: hook.path) {
            try? defaultHookScript.write(to: hook, atomically: true, encoding: .utf8)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        }
    }

    private static let defaultHookScript = """
    #!/usr/bin/env bash
    # Default Redline agent hook — invoked as: redline-agent-hook.sh <inbox-id> <bundle-dir>
    set -euo pipefail

    ITEM_ID="${1:?item id}"
    BUNDLE_DIR="${2:?bundle dir}"

    echo "[redline-agent-hook] item=$ITEM_ID"
    echo "[redline-agent-hook] bundle=$BUNDLE_DIR"

    if [[ -f "$BUNDLE_DIR/prompt.md" ]]; then
      echo "[redline-agent-hook] --- prompt.md (head) ---"
      head -n 40 "$BUNDLE_DIR/prompt.md"
      echo "[redline-agent-hook] --- end ---"
      # Open the prompt so something visible happens by default.
      open "$BUNDLE_DIR/prompt.md" 2>/dev/null || true
    else
      echo "[redline-agent-hook] warning: prompt.md missing"
      open "$BUNDLE_DIR" 2>/dev/null || true
    fi

    /usr/bin/osascript -e "display notification \\"Feedback $ITEM_ID ready\\" with title \\"Redline agent hook\\"" 2>/dev/null || true
    exit 0
    """
}
