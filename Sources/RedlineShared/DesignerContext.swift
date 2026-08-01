import Foundation

public struct DesignerPin: Codable, Equatable, Sendable {
    public var component: String
    public var pin: String

    public init(component: String, pin: String) {
        self.component = component
        self.pin = pin
    }
}

public protocol DesignerContext: Sendable {
    func pins(screen: String, region: String) -> [DesignerPin]
}

public struct EmptyDesignerContext: DesignerContext, Sendable {
    public init() {}

    public func pins(screen: String, region: String) -> [DesignerPin] {
        []
    }
}
