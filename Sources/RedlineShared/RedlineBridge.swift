import Foundation

public struct StartRedlineBridge: Codable, Equatable, Sendable {
    public var region: String
    public var nodeId: String?
    public var hierarchyPath: [String]?
    public var frame: InspectorFrame?
    public var measuredGaps: [MeasuredGap]?
    public var pins: [DesignerPin]

    public init(
        region: String,
        nodeId: String? = nil,
        hierarchyPath: [String]? = nil,
        frame: InspectorFrame? = nil,
        measuredGaps: [MeasuredGap]? = nil,
        pins: [DesignerPin] = []
    ) {
        self.region = region
        self.nodeId = nodeId
        self.hierarchyPath = hierarchyPath
        self.frame = frame
        self.measuredGaps = measuredGaps
        self.pins = pins
    }
}

public struct NodeAttributes: Codable, Equatable, Sendable {
    public var alpha: Double?
    public var isHidden: Bool?
    public var backgroundColor: String?
    public var frame: InspectorFrame?

    public init(
        alpha: Double? = nil,
        isHidden: Bool? = nil,
        backgroundColor: String? = nil,
        frame: InspectorFrame? = nil
    ) {
        self.alpha = alpha
        self.isHidden = isHidden
        self.backgroundColor = backgroundColor
        self.frame = frame
    }
}

public struct RedlineArchiveManifest: Codable, Equatable, Sendable {
    public var version: Int
    public var exportedAt: String
    public var app: InspectableAppInfo
    public var nodeCount: Int
    public var screenshotNodeIds: [String]

    public init(
        version: Int = 1,
        exportedAt: String,
        app: InspectableAppInfo,
        nodeCount: Int,
        screenshotNodeIds: [String] = []
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.app = app
        self.nodeCount = nodeCount
        self.screenshotNodeIds = screenshotNodeIds
    }
}

public enum RedlineBridge {
    public static func parentMap(in snapshot: HierarchySnapshot) -> [String: String] {
        var map: [String: String] = [:]
        for node in snapshot.nodes.values {
            for child in node.children {
                map[child] = node.id
            }
        }
        return map
    }

    public static func hierarchyPath(for nodeId: String, in snapshot: HierarchySnapshot) -> [String] {
        let parents = parentMap(in: snapshot)
        var path: [String] = []
        var current: String? = nodeId
        while let id = current, let node = snapshot.nodes[id] {
            path.insert(node.displayName, at: 0)
            current = parents[id]
        }
        return path
    }

    public static func resolveRegion(for nodeId: String, in snapshot: HierarchySnapshot) -> String? {
        let parents = parentMap(in: snapshot)
        var current: String? = nodeId
        while let id = current, let node = snapshot.nodes[id] {
            if let region = node.regionName {
                return region
            }
            current = parents[id]
        }
        return nil
    }

    public static func buildStartPayload(
        nodeId: String,
        in snapshot: HierarchySnapshot,
        measuredGaps: [MeasuredGap] = [],
        pins: [DesignerPin] = []
    ) -> StartRedlineBridge {
        let node = snapshot.nodes[nodeId]
        let region = resolveRegion(for: nodeId, in: snapshot)
            ?? node?.displayName
            ?? "Screen"
        return StartRedlineBridge(
            region: region,
            nodeId: nodeId,
            hierarchyPath: hierarchyPath(for: nodeId, in: snapshot),
            frame: node?.frame,
            measuredGaps: measuredGaps.isEmpty ? nil : measuredGaps,
            pins: pins
        )
    }

    public static func measureGap(from fromNode: HierarchyNode, to toNode: HierarchyNode) -> MeasuredGap {
        let fromFrame = fromNode.frame
        let toFrame = toNode.frame

        let dx: Double = if toFrame.x >= fromFrame.x + fromFrame.w {
            toFrame.x - (fromFrame.x + fromFrame.w)
        } else if fromFrame.x >= toFrame.x + toFrame.w {
            -((fromFrame.x) - (toFrame.x + toFrame.w))
        } else {
            toFrame.x - fromFrame.x
        }

        let dy: Double = if toFrame.y >= fromFrame.y + fromFrame.h {
            toFrame.y - (fromFrame.y + fromFrame.h)
        } else if fromFrame.y >= toFrame.y + toFrame.h {
            -((fromFrame.y) - (toFrame.y + toFrame.h))
        } else {
            0
        }

        return MeasuredGap(from: fromNode.id, to: toNode.id, dx: dx, dy: dy)
    }

    public static func inspectorPayload(from bridge: StartRedlineBridge) -> InspectorBridgePayload {
        InspectorBridgePayload(
            nodeId: bridge.nodeId,
            hierarchyPath: bridge.hierarchyPath,
            frame: bridge.frame,
            measuredGaps: bridge.measuredGaps
        )
    }
}
