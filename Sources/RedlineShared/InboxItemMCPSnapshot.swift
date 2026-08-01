import Foundation

/// Slim inbox item for MCP / HTTP clients — omits large `compositePngBase64`.
public struct InboxItemMCPSnapshot: Codable, Equatable, Sendable {
    public var id: String
    public var receivedAt: Date
    public var status: InboxItem.Status
    public var screen: String
    public var region: String
    public var comment: String
    public var state: String?
    public var platform: String
    public var mode: String?
    public var spec: String?
    public var capturedTs: String
    public var bundleDirectory: String?
    public var proposalSummary: String?
    public var runtime: AppRuntimeContext?
    public var compositeOmitted: Bool
    public var stagedFeedbackPath: String?

    public init(from item: InboxItem, stagedFeedbackPath: String? = nil) {
        id = item.id
        receivedAt = item.receivedAt
        status = item.status
        screen = item.payload.screen
        region = item.payload.region
        comment = item.payload.comment
        state = item.payload.state
        platform = item.payload.platform
        mode = item.payload.mode
        spec = item.payload.spec
        capturedTs = item.payload.capturedTs
        bundleDirectory = item.bundleDirectory
        proposalSummary = item.proposalSummary
        runtime = item.payload.runtime
        compositeOmitted = true
        // Only set when staging actually succeeded — do not invent `.redline-feedback`.
        self.stagedFeedbackPath = stagedFeedbackPath
    }

    /// Rebuild a minimal `InboxItem` for MCP/HTTP clients (composite intentionally empty).
    public func asInboxItem() -> InboxItem {
        InboxItem(
            id: id,
            receivedAt: receivedAt,
            status: status,
            payload: FeedbackPayload(
                screen: screen,
                region: region,
                state: state,
                platform: platform,
                mode: mode,
                spec: spec,
                capturedTs: capturedTs,
                comment: comment,
                pins: [],
                toolsUsed: [],
                strokes: [],
                compositePngBase64: "",
                inspector: nil,
                runtime: runtime
            ),
            bundleDirectory: bundleDirectory,
            proposalSummary: proposalSummary
        )
    }
}
