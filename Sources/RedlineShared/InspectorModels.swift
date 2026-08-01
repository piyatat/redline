import Foundation

public struct InspectableAppInfo: Codable, Equatable, Hashable, Sendable {
    public var bundleIdentifier: String
    public var appName: String
    public var serverVersion: Int
    public var platform: String

    public init(bundleIdentifier: String, appName: String, serverVersion: Int = 1, platform: String = "ios") {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.serverVersion = serverVersion
        self.platform = platform
    }
}

public struct HierarchyNode: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var framework: String
    public var className: String
    public var displayName: String
    public var frame: InspectorFrame
    public var isHidden: Bool
    public var alpha: Double
    public var children: [String]
    public var regionName: String?
    /// Lookin-style: layer alone (sublayers hidden). Used for 3D explode.
    public var soloPNGBase64: String?
    /// Lookin-style: layer with descendants. Fallback when solo is empty.
    public var groupPNGBase64: String?

    public init(
        id: String,
        framework: String,
        className: String,
        displayName: String,
        frame: InspectorFrame,
        isHidden: Bool = false,
        alpha: Double = 1,
        children: [String] = [],
        regionName: String? = nil,
        soloPNGBase64: String? = nil,
        groupPNGBase64: String? = nil
    ) {
        self.id = id
        self.framework = framework
        self.className = className
        self.displayName = displayName
        self.frame = frame
        self.isHidden = isHidden
        self.alpha = alpha
        self.children = children
        self.regionName = regionName
        self.soloPNGBase64 = soloPNGBase64
        self.groupPNGBase64 = groupPNGBase64
    }
}

public struct HierarchySnapshot: Codable, Equatable, Sendable {
    public var app: InspectableAppInfo
    public var roots: [String]
    public var nodes: [String: HierarchyNode]
    public var capturedAt: String

    public init(app: InspectableAppInfo, roots: [String], nodes: [String: HierarchyNode], capturedAt: String) {
        self.app = app
        self.roots = roots
        self.nodes = nodes
        self.capturedAt = capturedAt
    }
}

public enum InspectorRequestType: String, Codable, Sendable {
    case ping
    case hierarchy
    case snapshot
    case highlight
    case startRedline
    case attributes
    case setAttribute
    case measure
    case refreshNode
    case console
}

public struct InspectorRequest: Codable, Sendable {
    public var id: String
    public var type: InspectorRequestType
    public var nodeId: String?
    public var nodeIdB: String?
    public var attributeKey: String?
    public var attributeValue: String?
    public var bridge: StartRedlineBridge?
    public var captureOptions: HierarchyCaptureOptions?

    public init(
        id: String = UUID().uuidString,
        type: InspectorRequestType,
        nodeId: String? = nil,
        nodeIdB: String? = nil,
        attributeKey: String? = nil,
        attributeValue: String? = nil,
        bridge: StartRedlineBridge? = nil,
        captureOptions: HierarchyCaptureOptions? = nil
    ) {
        self.id = id
        self.type = type
        self.nodeId = nodeId
        self.nodeIdB = nodeIdB
        self.attributeKey = attributeKey
        self.attributeValue = attributeValue
        self.bridge = bridge
        self.captureOptions = captureOptions
    }
}

public struct InspectorResponse: Codable, Sendable {
    public var id: String
    public var ok: Bool
    public var error: String?
    public var app: InspectableAppInfo?
    public var hierarchy: HierarchySnapshot?
    public var pngBase64: String?
    public var attributes: NodeAttributes?
    public var measuredGap: MeasuredGap?
    public var refreshHint: Bool?
    public var consoleOutput: String?

    public init(
        id: String,
        ok: Bool,
        error: String? = nil,
        app: InspectableAppInfo? = nil,
        hierarchy: HierarchySnapshot? = nil,
        pngBase64: String? = nil,
        attributes: NodeAttributes? = nil,
        measuredGap: MeasuredGap? = nil,
        refreshHint: Bool? = nil,
        consoleOutput: String? = nil
    ) {
        self.id = id
        self.ok = ok
        self.error = error
        self.app = app
        self.hierarchy = hierarchy
        self.pngBase64 = pngBase64
        self.attributes = attributes
        self.measuredGap = measuredGap
        self.refreshHint = refreshHint
        self.consoleOutput = consoleOutput
    }
}
