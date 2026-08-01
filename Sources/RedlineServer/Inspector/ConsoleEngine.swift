#if os(iOS)
import UIKit
import RedlineShared

public enum ConsoleEngine {
    public static func evaluate(nodeId: String, expression: String) -> String {
        guard let view = CaptureEngine.view(forNodeId: nodeId) else {
            return "error: node not found"
        }

        switch expression.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "alpha":
            return String(format: "%.3f", view.alpha)
        case "hidden", "ishidden":
            return view.isHidden ? "true" : "false"
        case "frame":
            let f = view.frame
            return "x=\(f.origin.x) y=\(f.origin.y) w=\(f.width) h=\(f.height)"
        case "class", "classname":
            return String(describing: type(of: view))
        case "region":
            if let id = view.accessibilityIdentifier, id.hasPrefix("redlineRegion:") {
                return String(id.dropFirst("redlineRegion:".count))
            }
            return "nil"
        case "subviews":
            return String(view.subviews.count)
        case "help":
            return "expressions: alpha, hidden, frame, class, region, subviews"
        default:
            return "unknown expression '\(expression)' — type 'help'"
        }
    }
}
#endif
