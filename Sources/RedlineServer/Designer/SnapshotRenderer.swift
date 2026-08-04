#if os(iOS)
import UIKit
import RedlineShared

enum SnapshotRenderer {
    /// Captures the key window, then draws [strokes] into the PNG so Mac/agent
    /// receive markup visually (not only as JSON vectors).
    static func captureKeyWindowPNGBase64(strokes: [MarkupStroke] = []) -> String {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) else {
            return ""
        }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { ctx in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            guard !strokes.isEmpty else { return }
            let cg = ctx.cgContext
            cg.setLineWidth(3)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for stroke in strokes {
                cg.setStrokeColor(strokeUIColor(stroke.color).cgColor)
                let points = stroke.points.compactMap { pair -> CGPoint? in
                    guard pair.count == 2 else { return nil }
                    return CGPoint(x: pair[0], y: pair[1])
                }
                guard let first = points.first else { continue }
                switch stroke.tool {
                case "rect":
                    guard let last = points.last else { continue }
                    let rect = CGRect(
                        x: min(first.x, last.x),
                        y: min(first.y, last.y),
                        width: abs(last.x - first.x),
                        height: abs(last.y - first.y)
                    )
                    cg.stroke(rect)
                case "arrow":
                    guard let last = points.last else { continue }
                    cg.beginPath()
                    cg.move(to: first)
                    cg.addLine(to: last)
                    cg.strokePath()
                    let angle = atan2(last.y - first.y, last.x - first.x)
                    let head: CGFloat = 14
                    cg.beginPath()
                    cg.move(to: last)
                    cg.addLine(to: CGPoint(
                        x: last.x - head * cos(angle - .pi / 6),
                        y: last.y - head * sin(angle - .pi / 6)
                    ))
                    cg.move(to: last)
                    cg.addLine(to: CGPoint(
                        x: last.x - head * cos(angle + .pi / 6),
                        y: last.y - head * sin(angle + .pi / 6)
                    ))
                    cg.strokePath()
                default:
                    cg.beginPath()
                    cg.move(to: first)
                    for point in points.dropFirst() {
                        cg.addLine(to: point)
                    }
                    cg.strokePath()
                }
            }
        }
        return image.pngData()?.base64EncodedString() ?? ""
    }

    private static func strokeUIColor(_ id: String) -> UIColor {
        switch id {
        case "green": return .systemGreen
        case "neutral": return UIColor(white: 0.45, alpha: 1)
        default: return .systemRed
        }
    }
}
#endif
