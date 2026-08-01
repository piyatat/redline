import Foundation
import RedlineShared

/// Minimal MCP stdio server exposing Redline inbox tools for Cursor / Claude Code.
final class MCPStdioServer {
    private let client = RedlineHTTPClient()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    /// Ids already delivered/claimed by this MCP process — survives across wait calls.
    private var deliveredIds = Set<String>()
    private var seededDelivered = false

    func run() {
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
            guard let request = try? JSONDecoder().decode(MCPRequest.self, from: data) else { continue }

            // Notifications have no response.
            if request.method.hasPrefix("notifications/") || request.id == nil {
                continue
            }

            let response = handle(request)
            write(response)
        }
    }

    private func write(_ response: MCPResponse) {
        guard let out = try? encoder.encode(response),
              var text = String(data: out, encoding: .utf8) else { return }
        // Avoid Foundation's \/ escapes confusing clients.
        text = text.replacingOccurrences(of: "\\/", with: "/")
        print(text)
        fflush(stdout)
    }

    private func handle(_ request: MCPRequest) -> MCPResponse {
        switch request.method {
        case "initialize":
            return MCPResponse(
                id: request.id,
                result: MCPResult(
                    protocolVersion: "2024-11-05",
                    serverInfo: MCPServerInfo(name: "redline", version: "0.1.0"),
                    capabilities: MCPCapabilities(tools: MCPToolsCapability())
                )
            )
        case "ping":
            return MCPResponse(id: request.id, result: MCPResult())
        case "tools/list":
            return MCPResponse(id: request.id, result: MCPResult(tools: Self.tools))
        case "tools/call":
            return handleToolCall(request)
        default:
            return MCPResponse(
                id: request.id,
                error: MCPError(code: -32601, message: "Method not found: \(request.method)")
            )
        }
    }

    private func handleToolCall(_ request: MCPRequest) -> MCPResponse {
        guard let params = request.params, let name = params.name else {
            return MCPResponse(id: request.id, error: MCPError(message: "Missing tool name"))
        }

        do {
            switch name {
            case "redline_inbox_list":
                let items = try client.inboxList()
                let snapshots = items.map { InboxItemMCPSnapshot(from: $0) }
                let data = try encoder.encode(snapshots)
                return toolTextResponse(id: request.id, text: String(data: data, encoding: .utf8) ?? "[]")
            case "redline_inbox_show":
                let id = params.stringArgument("id") ?? ""
                let items = try client.inboxList()
                guard let item = items.first(where: { $0.id == id }) else {
                    return MCPResponse(id: request.id, error: MCPError(message: "Item not found"))
                }
                let staged = stageForWorkspace(item)
                let data = try encoder.encode(InboxItemMCPSnapshot(from: item, stagedFeedbackPath: staged))
                return toolTextResponse(id: request.id, text: String(data: data, encoding: .utf8) ?? "{}")
            case "redline_wait_for_feedback":
                let timeout = Double(params.stringArgument("timeoutSeconds") ?? "300") ?? 300
                let item = try waitForFeedback(timeout: timeout)
                let staged = stageForWorkspace(item)
                let data = try encoder.encode(InboxItemMCPSnapshot(from: item, stagedFeedbackPath: staged))
                return toolTextResponse(id: request.id, text: String(data: data, encoding: .utf8) ?? "{}")
            case "redline_inbox_set_status":
                let id = params.stringArgument("id") ?? ""
                let status = params.stringArgument("status") ?? ""
                let summary = params.stringArgument("summary")
                guard !id.isEmpty else {
                    return MCPResponse(id: request.id, error: MCPError(message: "Missing id"))
                }
                guard !status.isEmpty else {
                    return MCPResponse(
                        id: request.id,
                        error: MCPError(message: "Missing status — use pending|agent_running|applied|failed")
                    )
                }
                let item = try client.inboxSetStatus(id: id, status: status, summary: summary)
                let data = try encoder.encode(InboxItemMCPSnapshot(from: item))
                return toolTextResponse(id: request.id, text: String(data: data, encoding: .utf8) ?? "{}")
            case "redline_get_tree":
                let port = UInt16(params.stringArgument("port") ?? "\(RedlinePorts.simulatorInspectStart)")
                    ?? UInt16(RedlinePorts.simulatorInspectStart)
                let tree = try fetchTree(port: port)
                return toolTextResponse(id: request.id, text: tree)
            case "redline_gates_run":
                let workspace = URL(
                    fileURLWithPath: params.stringArgument("workspace")
                        ?? FileManager.default.currentDirectoryPath
                )
                let bundle = params.stringArgument("bundle").map { URL(fileURLWithPath: $0) }
                let result = GateRunner.run(workspaceRoot: workspace, bundleDirectory: bundle)
                let data = try encoder.encode(result)
                return toolTextResponse(id: request.id, text: String(data: data, encoding: .utf8) ?? "{}")
            default:
                return MCPResponse(id: request.id, error: MCPError(message: "Unknown tool \(name)"))
            }
        } catch {
            return MCPResponse(id: request.id, error: MCPError(message: error.localizedDescription))
        }
    }

    private func waitForFeedback(timeout: TimeInterval) throws -> InboxItem {
        let start = Date()
        if !seededDelivered {
            // Seed with non-pending so existing backlog pending items remain claimable;
            // already-running / finished work is never re-delivered.
            let existing = try client.inboxList()
            deliveredIds = Set(existing.filter { $0.status != .pending }.map(\.id))
            seededDelivered = true
        }

        while Date().timeIntervalSince(start) < timeout {
            let items = try client.inboxList()
            // Re-open: if we delivered an id that is pending again, allow reclaim.
            for item in items where item.status == .pending {
                deliveredIds.remove(item.id)
            }
            let candidates = items
                .filter { $0.status == .pending && !deliveredIds.contains($0.id) }
                .sorted { $0.receivedAt < $1.receivedAt }
            if let candidate = candidates.first {
                do {
                    let claimed = try client.inboxSetStatus(
                        id: candidate.id,
                        status: InboxItem.Status.agentRunning.rawValue,
                        summary: "Cursor MCP /redline-wait — in progress"
                    )
                    deliveredIds.insert(candidate.id)
                    return claimed
                } catch {
                    // Do not mark delivered — retry claim on next poll / next wait call.
                    throw RedlineHTTPError.badStatus(
                        409,
                        message: "Claim failed: \(error.localizedDescription)"
                    )
                }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        throw RedlineHTTPError.timeout("Timed out after \(Int(timeout))s waiting for new Redline feedback")
    }

    /// Stage bundle into `REDLINE_WORKSPACE_ROOT/.redline-feedback` when env is set.
    private func stageForWorkspace(_ item: InboxItem) -> String? {
        let workspace = ProcessInfo.processInfo.environment[RedlineEnvironment.workspaceRootKey]
        guard let url = FeedbackBundleStager.stageIfPossible(
            projectPath: workspace,
            bundleDirectory: item.bundleDirectory
        ) else {
            return nil
        }
        return url.path
    }

    private func fetchTree(port: UInt16) throws -> String {
        let sem = DispatchSemaphore(value: 0)
        var json = "{}"
        var err: Error?
        Task {
            do {
                let hierarchy = try await InspectorClient().fetchHierarchy(port: port)
                let data = try JSONEncoder().encode(hierarchy)
                json = String(data: data, encoding: .utf8) ?? "{}"
            } catch {
                err = error
            }
            sem.signal()
        }
        sem.wait()
        if let err { throw err }
        return json
    }

    private func toolTextResponse(id: MCPID?, text: String) -> MCPResponse {
        MCPResponse(
            id: id,
            result: MCPResult(content: [MCPContent(type: "text", text: text)])
        )
    }

    private static let tools: [MCPTool] = [
        MCPTool(
            name: "redline_inbox_list",
            description: "List Redline inbox items from the Mac receiver",
            inputSchema: MCPToolSchema(properties: [:], required: [])
        ),
        MCPTool(
            name: "redline_inbox_show",
            description: "Show one inbox item by id",
            inputSchema: MCPToolSchema(
                properties: ["id": MCPToolProperty(type: "string", description: "Inbox item id")],
                required: ["id"]
            )
        ),
        MCPTool(
            name: "redline_wait_for_feedback",
            description: "Block until a new Redline feedback item arrives (marks it agent_running)",
            inputSchema: MCPToolSchema(
                properties: [
                    "timeoutSeconds": MCPToolProperty(
                        type: "string",
                        description: "Seconds to wait (default 300)"
                    ),
                ],
                required: []
            )
        ),
        MCPTool(
            name: "redline_inbox_set_status",
            description: """
            Update a Redline inbox item status in the Mac app. Call with applied when the fix is done, \
            or failed if you could not complete it. status: pending | agent_running | applied | failed \
            (aliases: finished→applied, running→agent_running). Optional summary is shown in the Inbox.
            """,
            inputSchema: MCPToolSchema(
                properties: [
                    "id": MCPToolProperty(type: "string", description: "Inbox item id"),
                    "status": MCPToolProperty(
                        type: "string",
                        description: "pending | agent_running | applied | failed"
                    ),
                    "summary": MCPToolProperty(
                        type: "string",
                        description: "Short note for the Inbox detail pane"
                    ),
                ],
                required: ["id", "status"]
            )
        ),
        MCPTool(
            name: "redline_get_tree",
            description: "Fetch live hierarchy from the iOS inspector",
            inputSchema: MCPToolSchema(
                properties: [
                    "port": MCPToolProperty(type: "string", description: "Inspector TCP port"),
                ],
                required: []
            )
        ),
        MCPTool(
            name: "redline_gates_run",
            description: "Run Redline gate manifest against a workspace/bundle",
            inputSchema: MCPToolSchema(
                properties: [
                    "workspace": MCPToolProperty(type: "string", description: "Workspace root path"),
                    "bundle": MCPToolProperty(type: "string", description: "Feedback bundle path"),
                ],
                required: []
            )
        ),
    ]
}

// MARK: - JSON-RPC / MCP models

private struct MCPRequest: Decodable {
    var id: MCPID?
    var method: String
    var params: MCPToolParams?
}

private struct MCPToolParams: Decodable {
    var name: String?
    var arguments: [String: MCPArgumentValue]?

    func stringArgument(_ key: String) -> String? {
        arguments?[key]?.stringValue
    }
}

private enum MCPArgumentValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else {
            self = .null
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .number(let value):
            return value.rounded() == value ? String(Int(value)) : String(value)
        case .bool(let value): return value ? "true" : "false"
        case .null: return nil
        }
    }
}

private enum MCPID: Codable, Equatable {
    case string(String)
    case int(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.typeMismatch(
                MCPID.self,
                .init(codingPath: decoder.codingPath, debugDescription: "id must be string or number")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        }
    }
}

private struct MCPResponse: Encodable {
    var jsonrpc: String = "2.0"
    var id: MCPID?
    var result: MCPResult?
    var error: MCPError?
}

private struct MCPResult: Encodable {
    var protocolVersion: String?
    var serverInfo: MCPServerInfo?
    var capabilities: MCPCapabilities?
    var tools: [MCPTool]?
    var content: [MCPContent]?

    init(
        protocolVersion: String? = nil,
        serverInfo: MCPServerInfo? = nil,
        capabilities: MCPCapabilities? = nil,
        tools: [MCPTool]? = nil,
        content: [MCPContent]? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.serverInfo = serverInfo
        self.capabilities = capabilities
        self.tools = tools
        self.content = content
    }
}

private struct MCPServerInfo: Encodable {
    var name: String
    var version: String
}

private struct MCPCapabilities: Encodable {
    var tools: MCPToolsCapability
}

private struct MCPToolsCapability: Encodable {}

private struct MCPTool: Encodable {
    var name: String
    var description: String
    var inputSchema: MCPToolSchema
}

private struct MCPToolSchema: Encodable {
    var type: String = "object"
    var properties: [String: MCPToolProperty]
    var required: [String]
}

private struct MCPToolProperty: Encodable {
    var type: String
    var description: String?
}

private struct MCPContent: Encodable {
    var type: String
    var text: String
}

private struct MCPError: Encodable {
    var code: Int
    var message: String

    init(code: Int = -32603, message: String) {
        self.code = code
        self.message = message
    }
}
