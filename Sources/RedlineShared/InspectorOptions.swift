import Foundation

public enum InspectorConnectionKind: String, Codable, Sendable {
    case simulator
    case usb
    case localMac = "local_mac"
}

public struct HierarchyCaptureOptions: Codable, Equatable, Sendable {
    public var maxDepth: Int?
    public var fastMode: Bool
    /// Embed Lookin-style solo/group screenshots (needed for 3D explode).
    public var includeScreenshots: Bool

    public init(maxDepth: Int? = nil, fastMode: Bool = false, includeScreenshots: Bool = true) {
        self.maxDepth = maxDepth
        self.fastMode = fastMode
        self.includeScreenshots = includeScreenshots
    }

    public static let `default` = HierarchyCaptureOptions(includeScreenshots: false)
    public static let fast = HierarchyCaptureOptions(maxDepth: 10, fastMode: true, includeScreenshots: false)
    /// Heavier capture — embeds solo/group PNGs (slow; use sparingly).
    public static let withScreenshots = HierarchyCaptureOptions(includeScreenshots: true)
}
