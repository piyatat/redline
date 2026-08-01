import Foundation

public struct MarkupStroke: Codable, Equatable, Sendable {
    public var tool: String
    public var color: String
    public var points: [[Double]]

    public init(tool: String, color: String, points: [[Double]]) {
        self.tool = tool
        self.color = color
        self.points = points
    }
}

public struct InspectorFrame: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

public struct MeasuredGap: Codable, Equatable, Sendable {
    public var from: String
    public var to: String
    public var dx: Double
    public var dy: Double

    public init(from: String, to: String, dx: Double, dy: Double) {
        self.from = from
        self.to = to
        self.dx = dx
        self.dy = dy
    }
}

public struct InspectorBridgePayload: Codable, Equatable, Sendable {
    public var nodeId: String?
    public var hierarchyPath: [String]?
    public var frame: InspectorFrame?
    public var measuredGaps: [MeasuredGap]?
    public var attributes: [String: String]?

    public init(
        nodeId: String? = nil,
        hierarchyPath: [String]? = nil,
        frame: InspectorFrame? = nil,
        measuredGaps: [MeasuredGap]? = nil,
        attributes: [String: String]? = nil
    ) {
        self.nodeId = nodeId
        self.hierarchyPath = hierarchyPath
        self.frame = frame
        self.measuredGaps = measuredGaps
        self.attributes = attributes
    }
}

public struct FeedbackPayload: Codable, Equatable, Sendable {
    public static let currentSchema = 1

    public var schema: Int
    public var screen: String
    public var region: String
    public var state: String?
    public var platform: String
    public var mode: String?
    public var spec: String?
    public var capturedTs: String
    public var comment: String
    public var pins: [DesignerPin]
    public var toolsUsed: [String]
    public var strokes: [MarkupStroke]
    public var compositePngBase64: String
    public var inspector: InspectorBridgePayload?
    /// App / device / UI stack snapshot for agent investigation.
    public var runtime: AppRuntimeContext?

    public init(
        schema: Int = FeedbackPayload.currentSchema,
        screen: String,
        region: String,
        state: String? = nil,
        platform: String,
        mode: String? = nil,
        spec: String? = nil,
        capturedTs: String,
        comment: String,
        pins: [DesignerPin] = [],
        toolsUsed: [String] = [],
        strokes: [MarkupStroke] = [],
        compositePngBase64: String,
        inspector: InspectorBridgePayload? = nil,
        runtime: AppRuntimeContext? = nil
    ) {
        self.schema = schema
        self.screen = screen
        self.region = region
        self.state = state
        self.platform = platform
        self.mode = mode
        self.spec = spec
        self.capturedTs = capturedTs
        self.comment = comment
        self.pins = pins
        self.toolsUsed = toolsUsed
        self.strokes = strokes
        self.compositePngBase64 = compositePngBase64
        self.inspector = inspector
        self.runtime = runtime
    }
}

public enum FeedbackPayloadError: Error, LocalizedError {
    case unsupportedSchema(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "Unsupported feedback schema version: \(version)"
        }
    }
}

extension FeedbackPayload {
    public func validateSchema() throws {
        guard schema == Self.currentSchema else {
            throw FeedbackPayloadError.unsupportedSchema(schema)
        }
    }

    public static func decode(from data: Data) throws -> FeedbackPayload {
        let decoder = JSONDecoder()
        let payload = try decoder.decode(FeedbackPayload.self, from: data)
        try payload.validateSchema()
        return payload
    }

    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}
