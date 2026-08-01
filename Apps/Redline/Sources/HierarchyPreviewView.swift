import AppKit
import SceneKit
import SwiftUI
import RedlineShared

enum PreviewMode: String, CaseIterable, Identifiable {
    case flat = "2D"
    case exploded = "3D"
    var id: String { rawValue }
}

/// LookIn-style preview: 2D screenshot+frames (click to select) and 3D exploded layers.
struct HierarchyPreviewView: View {
    @ObservedObject var connections: ConnectionManager
    let snapshot: HierarchySnapshot
    @State private var mode: PreviewMode = .flat
    @State private var showAllFrames = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("", selection: $mode) {
                    ForEach(PreviewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 100)

                if mode == .flat {
                    Toggle("Frames", isOn: $showAllFrames)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                } else {
                    Text("Drag to orbit · click a layer to select")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            Group {
                switch mode {
                case .flat:
                    FlatPreviewRepresentable(
                        snapshot: snapshot,
                        image: connections.previewImage,
                        selectedNodeId: connections.selectedNodeId,
                        showAllFrames: showAllFrames,
                        onSelect: selectNode
                    )
                case .exploded:
                    ExplodedPreviewRepresentable(
                        snapshot: snapshot,
                        windowImage: connections.previewImage,
                        selectedNodeId: connections.selectedNodeId,
                        fetchSnapshot: { id in await connections.fetchNodeSnapshot(nodeId: id) },
                        onSelect: selectNode
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func selectNode(_ id: String) {
        connections.selectedNodeId = id
        connections.highlightSelectedNode()
        Task { await connections.loadAttributes(for: id) }
    }
}

// MARK: - 2D (AppKit — reliable click hit-testing)

private struct FlatPreviewRepresentable: NSViewRepresentable {
    let snapshot: HierarchySnapshot
    let image: NSImage?
    let selectedNodeId: String?
    let showAllFrames: Bool
    let onSelect: (String) -> Void

    func makeNSView(context: Context) -> FlatPreviewNSView {
        let view = FlatPreviewNSView()
        view.onSelect = onSelect
        view.apply(snapshot: snapshot, image: image, selectedNodeId: selectedNodeId, showAllFrames: showAllFrames)
        return view
    }

    func updateNSView(_ view: FlatPreviewNSView, context: Context) {
        view.onSelect = onSelect
        view.apply(snapshot: snapshot, image: image, selectedNodeId: selectedNodeId, showAllFrames: showAllFrames)
    }
}

final class FlatPreviewNSView: NSView {
    var onSelect: ((String) -> Void)?

    private var snapshot: HierarchySnapshot?
    private var image: NSImage?
    private var selectedNodeId: String?
    private var showAllFrames = true
    private var previewLayout = PreviewLayout.empty

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func apply(
        snapshot: HierarchySnapshot,
        image: NSImage?,
        selectedNodeId: String?,
        showAllFrames: Bool
    ) {
        self.snapshot = snapshot
        self.image = image
        self.selectedNodeId = selectedNodeId
        self.showAllFrames = showAllFrames
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        guard let snapshot else { return }
        previewLayout = PreviewLayout(snapshot: snapshot, in: bounds.size)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()

        if let image {
            image.draw(
                in: previewLayout.fit,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
        } else {
            let text = "Loading screenshot…" as NSString
            text.draw(
                at: CGPoint(x: bounds.midX - 60, y: bounds.midY),
                withAttributes: [
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .font: NSFont.systemFont(ofSize: 12),
                ]
            )
        }

        guard showAllFrames || selectedNodeId != nil else { return }

        for item in previewLayout.items {
            let selected = item.id == selectedNodeId
            if !showAllFrames && !selected { continue }

            let path = NSBezierPath(rect: item.rect.insetBy(dx: 0.5, dy: 0.5))
            if selected {
                NSColor.systemPink.withAlphaComponent(0.18).setFill()
                path.fill()
                NSColor.systemPink.setStroke()
                path.lineWidth = 2
                path.stroke()
            } else {
                (item.isRegion ? NSColor.systemOrange : NSColor.systemTeal)
                    .withAlphaComponent(0.55)
                    .setStroke()
                path.lineWidth = 0.8
                path.stroke()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let id = previewLayout.hitTest(point) {
            onSelect?(id)
            selectedNodeId = id
            needsDisplay = true
        }
    }
}

// MARK: - 3D exploded (LookInside-style)
// Root = window screenshot. Other cards = live per-view snapshots (NOT window crops).
// Crops of transparent chrome produced the floating white fragments.

private struct ExplodedPreviewRepresentable: NSViewRepresentable {
    let snapshot: HierarchySnapshot
    let windowImage: NSImage?
    let selectedNodeId: String?
    let fetchSnapshot: (String) async -> NSImage?
    let onSelect: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, fetchSnapshot: fetchSnapshot)
    }

    func makeNSView(context: Context) -> ClickableSCNView {
        let view = ClickableSCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 1)
        view.antialiasingMode = .multisampling4X
        view.onSelectNode = { id in context.coordinator.onSelect(id) }
        context.coordinator.rebuild(
            view: view,
            snapshot: snapshot,
            windowImage: windowImage,
            selectedNodeId: selectedNodeId
        )
        return view
    }

    func updateNSView(_ view: ClickableSCNView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.fetchSnapshot = fetchSnapshot
        view.onSelectNode = { id in context.coordinator.onSelect(id) }
        let identity = "\(snapshot.capturedAt)|\(snapshot.nodes.count)|\(windowImage?.size.width ?? 0)"
        if context.coordinator.snapshotIdentity != identity {
            context.coordinator.rebuild(
                view: view,
                snapshot: snapshot,
                windowImage: windowImage,
                selectedNodeId: selectedNodeId
            )
        } else {
            context.coordinator.updateSelection(selectedNodeId)
        }
    }

    final class Coordinator {
        var onSelect: (String) -> Void
        var fetchSnapshot: (String) async -> NSImage?
        var snapshotIdentity = ""
        private var nodesById: [String: SCNNode] = [:]
        private var selectedNodeId: String?
        private var loadTask: Task<Void, Never>?
        private let scale: Float = 0.1
        private let zGap: Float = 10.0

        init(
            onSelect: @escaping (String) -> Void,
            fetchSnapshot: @escaping (String) async -> NSImage?
        ) {
            self.onSelect = onSelect
            self.fetchSnapshot = fetchSnapshot
        }

        func rebuild(
            view: SCNView,
            snapshot: HierarchySnapshot,
            windowImage: NSImage?,
            selectedNodeId: String?
        ) {
            loadTask?.cancel()
            snapshotIdentity = "\(snapshot.capturedAt)|\(snapshot.nodes.count)|\(windowImage?.size.width ?? 0)"
            self.selectedNodeId = selectedNodeId
            nodesById.removeAll()

            let scene = SCNScene()
            let windowFrame = snapshot.roots.compactMap { snapshot.nodes[$0]?.frame }.first
                ?? InspectorFrame(x: 0, y: 0, w: 390, h: 844)

            var depthMemo: [String: Int] = [:]
            func assignDepth(_ id: String, d: Int) {
                depthMemo[id] = d
                for child in snapshot.nodes[id]?.children ?? [] {
                    assignDepth(child, d: d + 1)
                }
            }
            for root in snapshot.roots { assignDepth(root, d: 0) }

            let contentIds = Self.selectContentLayers(snapshot: snapshot, window: windowFrame, depthMemo: depthMemo)

            var minX = Float.greatestFiniteMagnitude
            var maxX = -Float.greatestFiniteMagnitude
            var minY = Float.greatestFiniteMagnitude
            var maxY = -Float.greatestFiniteMagnitude

            func place(id: String, frame: InspectorFrame, zIndex: Int, image: NSImage?, selected: Bool) {
                let w = max(Float(frame.w) * scale, 0.5)
                let h = max(Float(frame.h) * scale, 0.5)
                let x = Float(frame.x + frame.w / 2 - windowFrame.x) * scale
                let y = -Float(frame.y + frame.h / 2 - windowFrame.y) * scale
                let z = Float(zIndex) * zGap

                let plane = SCNPlane(width: CGFloat(w), height: CGFloat(h))
                plane.materials = [Self.makeMaterial(image: image, selected: selected, placeholder: image == nil)]
                let scn = SCNNode(geometry: plane)
                scn.name = id
                scn.position = SCNVector3(x, y, z)
                scn.renderingOrder = zIndex
                scene.rootNode.addChildNode(scn)
                nodesById[id] = scn

                minX = min(minX, x - w / 2)
                maxX = max(maxX, x + w / 2)
                minY = min(minY, y - h / 2)
                maxY = max(maxY, y + h / 2)
            }

            // z=0: full window
            if let rootId = snapshot.roots.first, let root = snapshot.nodes[rootId] {
                place(
                    id: rootId,
                    frame: root.frame,
                    zIndex: 0,
                    image: windowImage,
                    selected: rootId == selectedNodeId
                )
            }

            // Placeholders until per-view snapshots arrive (hidden until textured — avoid white junk).
            for (i, id) in contentIds.enumerated() {
                guard let node = snapshot.nodes[id] else { continue }
                place(
                    id: id,
                    frame: node.frame,
                    zIndex: i + 1,
                    image: nil,
                    selected: id == selectedNodeId
                )
                // Hide until snapshot loads.
                nodesById[id]?.isHidden = true
            }

            let cx: Float
            let cy: Float
            let extent: Float
            let maxZ = Float(contentIds.count) * zGap
            if minX == Float.greatestFiniteMagnitude {
                cx = 0; cy = 0
                extent = Float(max(windowFrame.w, windowFrame.h)) * scale
            } else {
                cx = (minX + maxX) / 2
                cy = (minY + maxY) / 2
                extent = max(maxX - minX, maxY - minY, 1)
            }

            let cameraNode = SCNNode()
            let camera = SCNCamera()
            camera.zNear = 0.1
            camera.zFar = 10_000
            camera.fieldOfView = 30
            cameraNode.camera = camera
            let distance = extent * 2.0 + 30
            cameraNode.position = SCNVector3(cx + extent * 0.15, cy + extent * 0.08, maxZ + distance)
            cameraNode.look(at: SCNVector3(cx, cy, maxZ * 0.35))
            scene.rootNode.addChildNode(cameraNode)

            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 1000
            ambient.light?.color = NSColor.white
            scene.rootNode.addChildNode(ambient)

            view.scene = scene
            view.pointOfView = cameraNode

            let fetch = fetchSnapshot
            let ids = contentIds
            loadTask = Task { @MainActor in
                for id in ids {
                    if Task.isCancelled { return }
                    let img = await fetch(id)
                    if Task.isCancelled { return }
                    guard let scn = self.nodesById[id] else { continue }
                    guard let img, Self.visibleRatio(img) >= 0.04 else {
                        scn.isHidden = true
                        continue
                    }
                    scn.geometry?.materials = [
                        Self.makeMaterial(image: img, selected: id == self.selectedNodeId, placeholder: false),
                    ]
                    scn.isHidden = false
                }
            }
        }

        func updateSelection(_ selectedNodeId: String?) {
            let previous = self.selectedNodeId
            self.selectedNodeId = selectedNodeId
            func tint(_ id: String?, on: Bool) {
                guard let id, let node = nodesById[id], let mat = node.geometry?.materials.first else { return }
                if on {
                    mat.multiply.contents = NSColor(calibratedRed: 1, green: 0.75, blue: 0.85, alpha: 1)
                    mat.emission.contents = NSColor.systemPink.withAlphaComponent(0.22)
                } else {
                    mat.multiply.contents = NSColor.white
                    mat.emission.contents = NSColor.black
                }
            }
            tint(previous, on: false)
            tint(selectedNodeId, on: true)
        }

        /// Mid-sized **leaf** layers only — parents' group shots paint all descendants.
        static func selectContentLayers(
            snapshot: HierarchySnapshot,
            window: InspectorFrame,
            depthMemo: [String: Int]
        ) -> [String] {
            let windowArea = max(window.w * window.h, 1)
            let leaves: [(String, Int)] = snapshot.nodes.compactMap { id, node in
                if snapshot.roots.contains(id) { return nil }
                if node.isHidden { return nil }
                if !node.children.isEmpty { return nil } // leaf only
                if node.className.contains("DesignerTouch") { return nil }
                let area = node.frame.w * node.frame.h
                if area < 40 * 12 { return nil }
                if area >= windowArea * 0.45 { return nil }
                return (id, depthMemo[id] ?? 0)
            }

            // Prefer deeper leaves (closer to real controls), cap count.
            return leaves
                .sorted { $0.1 > $1.1 }
                .prefix(16)
                .map(\.0)
                .sorted { (depthMemo[$0] ?? 0) < (depthMemo[$1] ?? 0) }
        }

        static func visibleRatio(_ image: NSImage) -> CGFloat {
            var rect = CGRect(origin: .zero, size: image.size)
            guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return 0 }
            let tw = min(cg.width, 64), th = min(cg.height, 64)
            guard tw > 0, th > 0,
                  let ctx = CGContext(
                    data: nil, width: tw, height: th,
                    bitsPerComponent: 8, bytesPerRow: tw * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return 0 }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: tw, height: th))
            guard let data = ctx.data else { return 0 }
            let ptr = data.bindMemory(to: UInt8.self, capacity: tw * th * 4)
            var visible = 0
            let total = tw * th
            for i in 0..<total where ptr[i * 4 + 3] > 20 { visible += 1 }
            return CGFloat(visible) / CGFloat(max(total, 1))
        }

        static func makeMaterial(image: NSImage?, selected: Bool, placeholder: Bool) -> SCNMaterial {
            let mat = SCNMaterial()
            mat.lightingModel = .constant
            mat.isDoubleSided = false
            mat.cullMode = .back
            mat.writesToDepthBuffer = true
            if let image {
                mat.diffuse.contents = image
            } else {
                mat.diffuse.contents = NSColor.clear
                mat.transparency = 1
            }
            if selected {
                mat.multiply.contents = NSColor(calibratedRed: 1, green: 0.75, blue: 0.85, alpha: 1)
                mat.emission.contents = NSColor.systemPink.withAlphaComponent(0.22)
            } else {
                mat.multiply.contents = NSColor.white
                mat.emission.contents = NSColor.black
            }
            return mat
        }
    }
}

final class ClickableSCNView: SCNView {
    var onSelectNode: ((String) -> Void)?
    private var mouseDownPoint: NSPoint?

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        // Still allow camera control — selection on mouseUp if little movement.
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let start = mouseDownPoint {
            let dx = point.x - start.x
            let dy = point.y - start.y
            if (dx * dx + dy * dy) < 16 {
                let hits = hitTest(
                    point,
                    options: [
                        .searchMode: SCNHitTestSearchMode.all.rawValue,
                        .boundingBoxOnly: false,
                        .ignoreHiddenNodes: true,
                    ]
                )
                if let id = hits.compactMap(\.node.name).first(where: { $0.hasPrefix("obj:") }) {
                    onSelectNode?(id)
                }
            }
        }
        mouseDownPoint = nil
        super.mouseUp(with: event)
    }
}

// MARK: - Shared 2D layout / hit-test

private struct PreviewLayout {
    struct Item {
        let id: String
        let rect: CGRect
        let area: CGFloat
        let isRegion: Bool
        let depth: Int
    }

    static let empty = PreviewLayout(fit: .zero, items: [])

    let fit: CGRect
    let items: [Item]

    init(fit: CGRect, items: [Item]) {
        self.fit = fit
        self.items = items
    }

    init(snapshot: HierarchySnapshot, in size: CGSize) {
        let padding: CGFloat = 12
        let available = CGSize(
            width: max(size.width - padding * 2, 1),
            height: max(size.height - padding * 2, 1)
        )

        let windowFrame = snapshot.roots.compactMap { snapshot.nodes[$0]?.frame }.first
            ?? InspectorFrame(x: 0, y: 0, w: 390, h: 844)
        let windowSize = CGSize(width: max(windowFrame.w, 1), height: max(windowFrame.h, 1))
        let scale = min(available.width / windowSize.width, available.height / windowSize.height)
        let drawn = CGSize(width: windowSize.width * scale, height: windowSize.height * scale)
        let fit = CGRect(
            x: (size.width - drawn.width) / 2,
            y: (size.height - drawn.height) / 2,
            width: drawn.width,
            height: drawn.height
        )

        var depthMemo: [String: Int] = [:]
        func depth(of id: String) -> Int {
            if let d = depthMemo[id] { return d }
            if let parent = snapshot.nodes.first(where: { $0.value.children.contains(id) })?.key {
                let d = depth(of: parent) + 1
                depthMemo[id] = d
                return d
            }
            depthMemo[id] = 0
            return 0
        }

        var built: [Item] = []
        built.reserveCapacity(snapshot.nodes.count)
        for (id, node) in snapshot.nodes {
            guard !node.isHidden, node.frame.w > 0.5, node.frame.h > 0.5 else { continue }
            let rect = CGRect(
                x: fit.minX + CGFloat(node.frame.x - windowFrame.x) * scale,
                y: fit.minY + CGFloat(node.frame.y - windowFrame.y) * scale,
                width: CGFloat(node.frame.w) * scale,
                height: CGFloat(node.frame.h) * scale
            )
            built.append(Item(
                id: id,
                rect: rect,
                area: max(rect.width * rect.height, 1),
                isRegion: node.regionName != nil,
                depth: depth(of: id)
            ))
        }

        // Prefer deepest + smallest when clicking stacked full-bleed views.
        self.fit = fit
        self.items = built.sorted {
            if $0.depth != $1.depth { return $0.depth > $1.depth }
            return $0.area < $1.area
        }
    }

    func hitTest(_ point: CGPoint) -> String? {
        items.first(where: { $0.rect.contains(point) })?.id
    }
}
