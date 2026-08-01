import Foundation

public struct InboxItem: Codable, Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, CaseIterable, Sendable {
        case pending
        case agentRunning = "agent_running"
        case applied
        case failed

        /// Statuses the user can set manually (not while a run is in progress).
        public static var manuallyAssignable: [Status] {
            [.pending, .applied, .failed]
        }

        public var displayName: String {
            switch self {
            case .pending: return "Pending"
            case .agentRunning: return "Running"
            case .applied: return "Finished"
            case .failed: return "Failed"
            }
        }

        /// Maps legacy propose / gate-rejected values from older installs.
        public static func fromPersisted(_ raw: String) -> Status {
            switch raw {
            case "pending": return .pending
            case "agent_running": return .agentRunning
            case "applied": return .applied
            case "failed": return .failed
            case "proposed": return .pending
            case "gate_rejected": return .failed
            default: return .pending
            }
        }

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Self.fromPersisted(raw)
        }
    }

    public var id: String
    public var receivedAt: Date
    public var status: Status
    public var payload: FeedbackPayload
    public var bundleDirectory: String?
    /// Short agent / inbox note shown in the detail pane (not a spec proposal).
    public var proposalSummary: String?
    public var proposalDiffPath: String?

    public init(
        id: String = UUID().uuidString,
        receivedAt: Date = Date(),
        status: Status = .pending,
        payload: FeedbackPayload,
        bundleDirectory: String? = nil,
        proposalSummary: String? = nil,
        proposalDiffPath: String? = nil
    ) {
        self.id = id
        self.receivedAt = receivedAt
        self.status = status
        self.payload = payload
        self.bundleDirectory = bundleDirectory
        self.proposalSummary = proposalSummary
        self.proposalDiffPath = proposalDiffPath
    }
}

public struct AgentSettings: Codable, Equatable, Sendable {
    public var onNewFeedback: AgentTriggerMode
    public var agentBackend: AgentBackend
    public var projectPath: String?
    /// Absolute path to the Redline SPM checkout (for Cursor MCP install / `redline mcp`).
    public var redlinePackagePath: String?
    public var cursorAgentPath: String?
    public var claudeAgentPath: String?
    public var workspaceRoot: String?
    public var hookPath: String?
    public var consentExternalAi: Bool
    public var apiToken: String?
    public var maxFeedbackBodyBytes: Int
    /// Base app text size in points (11…20). Scales the whole UI via Dynamic Type.
    public var logFontSize: Double

    public static let logFontSizeDefault: Double = 14
    public static let logFontSizeRange: ClosedRange<Double> = 11...20

    public init(
        onNewFeedback: AgentTriggerMode = .triggerAgent,
        agentBackend: AgentBackend = .cursorCLI,
        projectPath: String? = nil,
        redlinePackagePath: String? = nil,
        cursorAgentPath: String? = nil,
        claudeAgentPath: String? = nil,
        workspaceRoot: String? = nil,
        hookPath: String? = nil,
        consentExternalAi: Bool = false,
        apiToken: String? = nil,
        maxFeedbackBodyBytes: Int = 8 * 1024 * 1024,
        logFontSize: Double = AgentSettings.logFontSizeDefault
    ) {
        self.onNewFeedback = onNewFeedback
        self.agentBackend = agentBackend
        self.projectPath = projectPath
        self.redlinePackagePath = redlinePackagePath
        self.cursorAgentPath = cursorAgentPath
        self.claudeAgentPath = claudeAgentPath
        self.workspaceRoot = workspaceRoot
        self.hookPath = hookPath
        self.consentExternalAi = consentExternalAi
        self.apiToken = apiToken
        self.maxFeedbackBodyBytes = maxFeedbackBodyBytes
        self.logFontSize = Self.clampedLogFontSize(logFontSize)
    }

    public static var defaults: AgentSettings { AgentSettings() }

    public static func clampedLogFontSize(_ size: Double) -> Double {
        min(max(size, logFontSizeRange.lowerBound), logFontSizeRange.upperBound)
    }

    enum CodingKeys: String, CodingKey {
        case onNewFeedback, agentBackend, projectPath, redlinePackagePath, cursorAgentPath, claudeAgentPath
        case workspaceRoot, hookPath, consentExternalAi
        case apiToken, maxFeedbackBodyBytes, logFontSize
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        onNewFeedback = try container.decodeIfPresent(AgentTriggerMode.self, forKey: .onNewFeedback) ?? .triggerAgent
        agentBackend = try container.decodeIfPresent(AgentBackend.self, forKey: .agentBackend) ?? .cursorCLI
        projectPath = try container.decodeIfPresent(String.self, forKey: .projectPath)
        redlinePackagePath = try container.decodeIfPresent(String.self, forKey: .redlinePackagePath)
        cursorAgentPath = try container.decodeIfPresent(String.self, forKey: .cursorAgentPath)
        claudeAgentPath = try container.decodeIfPresent(String.self, forKey: .claudeAgentPath)
        workspaceRoot = try container.decodeIfPresent(String.self, forKey: .workspaceRoot)
        hookPath = try container.decodeIfPresent(String.self, forKey: .hookPath)
        consentExternalAi = try container.decodeIfPresent(Bool.self, forKey: .consentExternalAi) ?? false
        apiToken = try container.decodeIfPresent(String.self, forKey: .apiToken)
        maxFeedbackBodyBytes = try container.decodeIfPresent(Int.self, forKey: .maxFeedbackBodyBytes) ?? 8 * 1024 * 1024
        logFontSize = Self.clampedLogFontSize(
            try container.decodeIfPresent(Double.self, forKey: .logFontSize) ?? Self.logFontSizeDefault
        )
    }
}

public struct AgentJob: Identifiable, Sendable {
    public let id: String
    public let inboxItemId: String
    public let bundleDirectory: URL

    public init(id: String = UUID().uuidString, inboxItemId: String, bundleDirectory: URL) {
        self.id = id
        self.inboxItemId = inboxItemId
        self.bundleDirectory = bundleDirectory
    }
}
