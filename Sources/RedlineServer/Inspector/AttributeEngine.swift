#if os(iOS)
import UIKit
import RedlineShared

public enum AttributeEngine {
    public static func read(nodeId: String) -> NodeAttributes? {
        guard let view = CaptureEngine.view(forNodeId: nodeId) else { return nil }
        return NodeAttributes(
            alpha: Double(view.alpha),
            isHidden: view.isHidden,
            backgroundColor: colorHex(view.backgroundColor),
            frame: {
                if let window = view.window {
                    return view.convert(view.bounds, to: window).inspectorFrame
                }
                return view.frame.inspectorFrame
            }()
        )
    }

    @discardableResult
    public static func write(nodeId: String, key: String, value: String) -> Bool {
        guard let view = CaptureEngine.view(forNodeId: nodeId) else { return false }
        switch key {
        case "alpha":
            guard let alpha = Double(value) else { return false }
            view.alpha = CGFloat(alpha)
            return true
        case "isHidden":
            view.isHidden = value == "true" || value == "1"
            return true
        case "backgroundColor":
            view.backgroundColor = colorFromHex(value) ?? view.backgroundColor
            return true
        default:
            return false
        }
    }

    private static func colorHex(_ color: UIColor?) -> String? {
        guard let color else { return nil }
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    private static func colorFromHex(_ hex: String) -> UIColor? {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }
}

private extension CGRect {
    var inspectorFrame: InspectorFrame {
        InspectorFrame(x: Double(origin.x), y: Double(origin.y), w: Double(width), h: Double(height))
    }
}
#endif
