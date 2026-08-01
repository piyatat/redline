import Foundation

public enum RedlinePorts {
    public static let feedbackDefault = 8765
    public static let feedbackScanEnd = 8780

    public static let simulatorInspectStart = 47164
    public static let simulatorInspectEnd = 47169

    public static let usbInspectStart = 47175
    public static let usbInspectEnd = 47179
}

public enum RedlinePaths {
    public static let feedbackRoute = "/feedback"
    public static let inboxRoute = "/inbox"
    public static let healthRoute = "/health"

    /// `POST /inbox/<id>/status` — agent / MCP status updates.
    public static func inboxStatusRoute(id: String) -> String {
        "/inbox/\(id)/status"
    }

    /// Returns inbox item id when `path` is `/inbox/<id>/status`.
    public static func inboxStatusItemId(from path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 3, parts[0] == "inbox", parts[2] == "status", !parts[1].isEmpty else {
            return nil
        }
        return parts[1]
    }
}

public enum RedlineEnvironment {
    public static let feedbackURLKey = "REDLINE_FEEDBACK_URL"
    public static let agentHookKey = "REDLINE_AGENT_HOOK"
    public static let workspaceRootKey = "REDLINE_WORKSPACE_ROOT"
    public static let onNewFeedbackKey = "REDLINE_ON_NEW_FEEDBACK"
    public static let gateManifestKey = "REDLINE_GATE_MANIFEST"
    public static let appcastURLKey = "REDLINE_APPCAST_URL"
    /// Shared bearer token for Mac receiver ↔ iOS/CLI (`Authorization: Bearer …`).
    public static let apiTokenKey = "REDLINE_API_TOKEN"
}

public enum AgentBackend: String, Codable, CaseIterable, Sendable {
    case cursorCLI = "cursor_cli"
    case claudeCLI = "claude_cli"
    case shellHook = "shell_hook"

    public var displayName: String {
        switch self {
        case .cursorCLI: return "Cursor Agent CLI"
        case .claudeCLI: return "Claude Code CLI"
        case .shellHook: return "Shell hook"
        }
    }

    /// Short help for Settings.
    public var summary: String {
        switch self {
        case .cursorCLI:
            return "Runs Cursor’s headless `agent` in your project folder (`agent -p --force`)."
        case .claudeCLI:
            return "Runs Claude Code in your project folder (`claude -p --permission-mode acceptEdits`)."
        case .shellHook:
            return "Runs a local script: `<hook> <inbox-id> <bundle-dir>`. Default opens `prompt.md` only."
        }
    }
}

public enum AgentTriggerMode: String, Codable, CaseIterable, Sendable {
    case off
    case notify
    /// Store + notify; leave work for Cursor desktop MCP (`/redline-wait`). Never auto-runs CLI.
    case awaitDesktopMCP = "await_desktop_mcp"
    case triggerAgent = "trigger_agent"

    /// Preferred order in Settings.
    public static var settingsOrder: [AgentTriggerMode] {
        [.awaitDesktopMCP, .triggerAgent, .notify, .off]
    }

    public var title: String {
        switch self {
        case .awaitDesktopMCP: return "Cursor desktop (MCP)"
        case .triggerAgent: return "Agent CLI"
        case .notify: return "Notify only"
        case .off: return "Off — manual"
        }
    }

    /// One-line explanation shown under the mode title.
    public var summary: String {
        switch self {
        case .awaitDesktopMCP:
            return "Best for Cursor desktop + `/redline-wait` (MCP plugins stay available). Save on device — Redline will not start Agent CLI."
        case .triggerAgent:
            return "On each Save, Redline starts the selected CLI (Cursor Agent or Claude) in your project folder."
        case .notify:
            return "Saves the feedback bundle and shows a notification. Nothing runs until you use Send to AI."
        case .off:
            return "Quiet inbox. Bundles are stored; use Send to AI on an item when you want an agent run."
        }
    }

    /// Maps legacy propose / auto-apply modes onto trigger agent.
    public static func fromPersisted(_ raw: String) -> AgentTriggerMode {
        switch raw {
        case "off": return .off
        case "notify": return .notify
        case "await_desktop_mcp", "desktop_mcp", "mcp": return .awaitDesktopMCP
        case "trigger_agent", "trigger_propose", "trigger_auto_apply": return .triggerAgent
        default: return .triggerAgent
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self.fromPersisted(raw)
    }
}
