import Foundation

public struct DiscoveredApp: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { "\(host):\(port)" }
    public var host: String
    public var port: UInt16
    public var app: InspectableAppInfo
    public var connectionKind: InspectorConnectionKind

    public init(
        host: String,
        port: UInt16,
        app: InspectableAppInfo,
        connectionKind: InspectorConnectionKind = .simulator
    ) {
        self.host = host
        self.port = port
        self.app = app
        self.connectionKind = connectionKind
    }
}
