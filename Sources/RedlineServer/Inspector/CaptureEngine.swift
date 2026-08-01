#if os(iOS)
import UIKit
import RedlineShared

/// Captures hierarchy the Lookin/LookInside way: walk `CALayer` trees (critical for SwiftUI
/// hosting views) and attach solo + group screenshots per layer.
public enum CaptureEngine {
    private static var nextID = 0
    /// Parallel to node ids `obj:N` — used for highlight / attributes.
    private static var capturedLayers: [CALayer] = []

    public static func captureHierarchy(options: HierarchyCaptureOptions = .default) -> HierarchySnapshot {
        var nodes: [String: HierarchyNode] = [:]
        var roots: [String] = []
        nextID = 0
        capturedLayers = []

        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }

        for scene in scenes {
            for window in scene.windows where !window.isHidden {
                let id = walkLayer(
                    window.layer,
                    rootLayer: window.layer,
                    nodes: &nodes,
                    depth: 0,
                    options: options
                )
                roots.append(id)
            }
        }

        return makeSnapshot(roots: roots, nodes: nodes)
    }

    public static func captureSubtree(nodeId: String, options: HierarchyCaptureOptions = .default) -> HierarchySnapshot? {
        guard let layer = layer(forNodeId: nodeId) else { return nil }
        var nodes: [String: HierarchyNode] = [:]
        nextID = 0
        capturedLayers = []
        let rootLayer = layer
        let root = walkLayer(layer, rootLayer: rootLayer, nodes: &nodes, depth: 0, options: options)
        return makeSnapshot(roots: [root], nodes: nodes)
    }

    private static func makeSnapshot(roots: [String], nodes: [String: HierarchyNode]) -> HierarchySnapshot {
        let info = InspectableAppInfo(
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown",
            appName: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "App"
        )
        return HierarchySnapshot(
            app: info,
            roots: roots,
            nodes: nodes,
            capturedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    @discardableResult
    private static func walkLayer(
        _ layer: CALayer,
        rootLayer: CALayer,
        nodes: inout [String: HierarchyNode],
        depth: Int,
        options: HierarchyCaptureOptions
    ) -> String {
        let id = "obj:\(nextID)"
        nextID += 1
        capturedLayers.append(layer)

        let hostView = layer.delegate as? UIView
        let region: String? = {
            if let aid = hostView?.accessibilityIdentifier, aid.hasPrefix("redlineRegion:") {
                return String(aid.dropFirst("redlineRegion:".count))
            }
            return nil
        }()

        let className: String = {
            if let hostView { return String(describing: type(of: hostView)) }
            return String(describing: type(of: layer))
        }()

        let displayName: String = {
            if let region { return region }
            if let label = hostView?.accessibilityLabel, !label.isEmpty { return label }
            return className
        }()

        // Window / root-layer coordinates (Lookin uses layer space relative to window).
        let frameRect = layer.convert(layer.bounds, to: rootLayer)

        var soloPNG: String?
        var groupPNG: String?
        if options.includeScreenshots, !options.fastMode || depth <= 6 {
            groupPNG = encodePNG(groupScreenshot(of: layer, lowQuality: options.fastMode || depth > 4))
            soloPNG = encodePNG(soloScreenshot(of: layer, lowQuality: options.fastMode || depth > 4))
        } else if options.includeScreenshots, depth <= 2 {
            // Fast mode: still capture shallow layers for 3D backplate + first explode cards.
            groupPNG = encodePNG(groupScreenshot(of: layer, lowQuality: true))
            soloPNG = encodePNG(soloScreenshot(of: layer, lowQuality: true))
        }

        let node = HierarchyNode(
            id: id,
            framework: hostView != nil ? "uikit" : "calayer",
            className: className,
            displayName: displayName,
            frame: frameRect.inspectorFrame,
            isHidden: layer.isHidden || (hostView?.isHidden ?? false),
            alpha: Double(layer.opacity),
            children: [],
            regionName: region,
            soloPNGBase64: soloPNG,
            groupPNGBase64: groupPNG
        )
        nodes[id] = node

        var childIDs: [String] = []
        let withinDepth = options.maxDepth.map { depth < $0 } ?? true
        if withinDepth, let sublayers = layer.sublayers {
            for sub in sublayers {
                if options.fastMode, sub.isHidden || sub.opacity < 0.01 { continue }
                // Skip LookInside/Redline overlays.
                if let v = sub.delegate as? UIView, String(describing: type(of: v)).contains("DesignerTouch") {
                    continue
                }
                childIDs.append(
                    walkLayer(sub, rootLayer: rootLayer, nodes: &nodes, depth: depth + 1, options: options)
                )
            }
        }
        if var current = nodes[id] {
            current.children = childIDs
            nodes[id] = current
        }

        return id
    }

    // MARK: - Screenshots (Lookin CALayer+LookinServer)

    /// Full layer including descendants.
    private static func groupScreenshot(of layer: CALayer, lowQuality: Bool) -> UIImage? {
        render(layer: layer, hideSublayers: false, lowQuality: lowQuality)
    }

    /// Layer alone — temporarily hide sublayers (Lookin soloScreenshot).
    private static func soloScreenshot(of layer: CALayer, lowQuality: Bool) -> UIImage? {
        guard let sublayers = layer.sublayers, !sublayers.isEmpty else {
            return render(layer: layer, hideSublayers: false, lowQuality: lowQuality)
        }
        return render(layer: layer, hideSublayers: true, lowQuality: lowQuality)
    }

    private static func render(layer: CALayer, hideSublayers: Bool, lowQuality: Bool) -> UIImage? {
        let size = layer.bounds.size
        guard size.width > 0.5, size.height > 0.5, size.width < 20_000, size.height < 20_000 else {
            return nil
        }

        var hiddenLayers: [CALayer] = []
        var hiddenViews: [UIView] = []
        if hideSublayers {
            if let sublayers = layer.sublayers {
                for sub in sublayers where !sub.isHidden {
                    sub.isHidden = true
                    hiddenLayers.append(sub)
                }
            }
            // drawViewHierarchy respects UIView.isHidden more reliably than layer.hidden alone.
            if let host = layer.delegate as? UIView {
                for sub in host.subviews where !sub.isHidden {
                    sub.isHidden = true
                    hiddenViews.append(sub)
                }
            }
        }
        defer {
            for sub in hiddenLayers { sub.isHidden = false }
            for view in hiddenViews { view.isHidden = false }
        }

        let maxPx: CGFloat = lowQuality ? 256 : 512
        let screenScale = UIScreen.main.scale
        let pixelMax = max(size.width, size.height) * screenScale
        let renderScale: CGFloat = pixelMax > maxPx ? min(screenScale * maxPx / pixelMax, 1) : 0

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = renderScale == 0 ? screenScale : renderScale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let hostView = layer.delegate as? UIView
            if let hostView {
                hostView.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
            } else {
                layer.render(in: ctx.cgContext)
            }
        }
    }

    private static func encodePNG(_ image: UIImage?) -> String? {
        image?.pngData()?.base64EncodedString()
    }

    public static func snapshotPNGBase64(nodeId: String, in hierarchy: HierarchySnapshot) -> String? {
        if let node = hierarchy.nodes[nodeId] {
            if let group = node.groupPNGBase64 { return group }
            if let solo = node.soloPNGBase64 { return solo }
        }
        return liveSnapshotPNGBase64(nodeId: nodeId)
    }

    /// Snapshot one layer using the last captured layer index (Lookin-style **solo** shot).
    public static func liveSnapshotPNGBase64(nodeId: String) -> String? {
        if layer(forNodeId: nodeId) == nil {
            _ = captureHierarchy(options: .default)
        }
        guard let layer = layer(forNodeId: nodeId) else { return nil }
        // Solo = hide sublayers first. Group shots include children and look like
        // duplicate full screens stacked in 3D.
        return encodePNG(soloScreenshot(of: layer, lowQuality: false))
    }

    static func view(forNodeId id: String) -> UIView? {
        layer(forNodeId: id)?.delegate as? UIView
    }

    static func layer(forNodeId id: String) -> CALayer? {
        guard id.hasPrefix("obj:"), let index = Int(id.dropFirst(4)),
              index >= 0, index < capturedLayers.count else { return nil }
        return capturedLayers[index]
    }

    public static func highlight(nodeId: String) {
        guard let view = view(forNodeId: nodeId) else {
            // Fall back to layer border.
            guard let layer = layer(forNodeId: nodeId) else { return }
            let original = layer.borderWidth
            let originalColor = layer.borderColor
            layer.borderWidth = 3
            layer.borderColor = UIColor.systemPink.cgColor
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                layer.borderWidth = original
                layer.borderColor = originalColor
            }
            return
        }
        let original = view.layer.borderWidth
        let originalColor = view.layer.borderColor
        view.layer.borderWidth = 3
        view.layer.borderColor = UIColor.systemPink.cgColor
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            view.layer.borderWidth = original
            view.layer.borderColor = originalColor
        }
    }
}

private extension CGRect {
    var inspectorFrame: InspectorFrame {
        InspectorFrame(x: Double(origin.x), y: Double(origin.y), w: Double(width), h: Double(height))
    }
}
#endif
