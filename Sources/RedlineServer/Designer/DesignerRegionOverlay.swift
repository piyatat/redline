#if os(iOS)
import SwiftUI
import UIKit

struct DesignerRegionOverlay: UIViewRepresentable {
    var isActive: Bool

    func makeUIView(context: Context) -> DesignerRegionOverlayView {
        DesignerRegionOverlayView()
    }

    func updateUIView(_ uiView: DesignerRegionOverlayView, context: Context) {
        uiView.isActive = isActive
        uiView.setNeedsDisplay()
    }
}

final class DesignerRegionOverlayView: UIView {
    var isActive = false {
        didSet { isUserInteractionEnabled = isActive }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        longPress.minimumPressDuration = 0.35
        addGestureRecognizer(longPress)

        // Simulator-friendly: single tap also opens markup.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard isActive else { return false }
        // Only steal hits inside tagged regions so chrome (e.g. Exit designer) still works.
        let windowPoint = convert(point, to: nil)
        return Self.regionName(at: windowPoint) != nil
    }

    override func draw(_ rect: CGRect) {
        guard isActive else { return }
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setStrokeColor(UIColor.systemOrange.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(2)

        for regionView in Self.regionViews() {
            let frame = regionView.convert(regionView.bounds, to: self)
            context.stroke(frame.insetBy(dx: 1, dy: 1))
        }
    }

    @objc private func handlePress(_ recognizer: UIGestureRecognizer) {
        guard isActive else { return }
        if let longPress = recognizer as? UILongPressGestureRecognizer, longPress.state != .began {
            return
        }
        if recognizer is UITapGestureRecognizer, recognizer.state != .ended {
            return
        }
        let point = recognizer.location(in: nil)
        let region = Self.regionName(at: point) ?? "Screen"
        Task { @MainActor in
            DesignerModeController.shared.beginMarkup(forRegion: region)
        }
    }

    private static func regionViews() -> [UIView] {
        var results: [UIView] = []
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows where !window.isHidden {
                collectRegions(in: window, into: &results)
            }
        }
        return results
    }

    private static func collectRegions(in view: UIView, into results: inout [UIView]) {
        if let id = view.accessibilityIdentifier, id.hasPrefix("redlineRegion:") {
            results.append(view)
        }
        for sub in view.subviews {
            collectRegions(in: sub, into: &results)
        }
    }

    /// Resolve region by frame containment — hitTest would return this overlay itself.
    private static func regionName(at windowPoint: CGPoint) -> String? {
        var best: (name: String, area: CGFloat)?
        for regionView in regionViews() {
            let frame = regionView.convert(regionView.bounds, to: nil)
            guard frame.contains(windowPoint) else { continue }
            guard let id = regionView.accessibilityIdentifier, id.hasPrefix("redlineRegion:") else { continue }
            let name = String(id.dropFirst("redlineRegion:".count))
            let area = frame.width * frame.height
            if let current = best {
                if area < current.area { best = (name, area) }
            } else {
                best = (name, area)
            }
        }
        return best?.name
    }
}
#endif
