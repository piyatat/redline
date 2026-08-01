#if os(iOS) && canImport(SwiftUI)
import SwiftUI
import RedlineShared

public struct DesignerMarkupView: View {
    @ObservedObject private var controller = DesignerModeController.shared
    @State private var currentTool = "pen"
    @State private var currentColor = "red"
    @State private var currentPoints: [CGPoint] = []
    @State private var showComment = false
    @State private var toolbarVisible = true

    public init() {}

    private var isWholeScreen: Bool {
        (controller.activeRegion ?? DesignerModeController.screenRegionName)
            == DesignerModeController.screenRegionName
    }

    public var body: some View {
        let region = controller.activeRegion ?? DesignerModeController.screenRegionName

        ZStack {
            if !isWholeScreen {
                Color.black.opacity(0.28).ignoresSafeArea()
            }

            MarkupCanvas(
                strokes: $controller.strokes,
                currentTool: $currentTool,
                currentColor: $currentColor,
                currentPoints: $currentPoints,
                onStrokeEnded: { controller.toolsUsed.insert(currentTool) }
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                if toolbarVisible {
                    MarkupToolbar(
                        regionLabel: region,
                        currentTool: $currentTool,
                        currentColor: $currentColor,
                        comment: $controller.markupComment,
                        showComment: $showComment,
                        canUndo: !controller.strokes.isEmpty,
                        onUndo: { _ = controller.strokes.popLast() },
                        onClear: { controller.strokes = [] },
                        onHide: { toolbarVisible = false },
                        onCancel: {
                            showComment = false
                            controller.showMarkup = false
                        },
                        onSave: { Task { await controller.saveMarkup() } }
                    )
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    HStack {
                        Button {
                            toolbarVisible = true
                        } label: {
                            Label("Show tools", systemImage: "chevron.down")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .shadow(color: .black.opacity(0.1), radius: 6, y: 1)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer(minLength: 0)
            }
            // Keep chrome below status bar / Dynamic Island so controls stay tappable.
            .padding(.top, 4)
            .animation(.easeInOut(duration: 0.2), value: toolbarVisible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MarkupToolbar: View {
    var regionLabel: String
    @Binding var currentTool: String
    @Binding var currentColor: String
    @Binding var comment: String
    @Binding var showComment: Bool
    var canUndo: Bool
    var onUndo: () -> Void
    var onClear: () -> Void
    var onHide: () -> Void
    var onCancel: () -> Void
    var onSave: () -> Void

    private let hitSize: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showComment {
                TextField("Comment for agent…", text: $comment)
                    .font(.subheadline)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(spacing: 2) {
                // Line 1 — draw tools + colors
                HStack(spacing: 2) {
                    Text(regionLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.leading, 8)
                    Spacer(minLength: 4)
                    toolIcon("pen", "pencil.tip")
                    toolIcon("arrow", "arrow.up.right")
                    toolIcon("rect", "rectangle")
                    thinDivider
                    colorSwatch("red", .red)
                    colorSwatch("green", .green)
                    colorSwatch("neutral", Color(white: 0.55))
                    Spacer(minLength: 0)
                }

                // Line 2 — edit + comment + cancel/save + hide
                HStack(spacing: 2) {
                    Spacer(minLength: 0)
                    iconButton("arrow.uturn.backward", enabled: canUndo, action: onUndo)
                    iconButton("trash", enabled: canUndo, action: onClear)
                    iconButton(
                        showComment ? "text.bubble.fill" : "text.bubble",
                        selected: showComment,
                        action: { showComment.toggle() }
                    )
                    thinDivider
                    iconButton("xmark", action: onCancel)
                        .accessibilityLabel("Cancel")
                    iconButton("checkmark", tint: .accentColor, action: onSave)
                        .accessibilityLabel("Save")
                    thinDivider
                    iconButton("chevron.up", action: onHide)
                        .accessibilityLabel("Hide toolbar")
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 6, y: 1)
        }
        .frame(maxWidth: .infinity)
    }

    private var thinDivider: some View {
        Capsule()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 22)
            .padding(.horizontal, 2)
    }

    private func toolIcon(_ id: String, _ systemName: String) -> some View {
        let selected = currentTool == id
        return Button {
            currentTool = id
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: hitSize, height: hitSize)
                .background(selected ? Color.accentColor : Color.clear)
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(id)
    }

    private func colorSwatch(_ id: String, _ color: Color) -> some View {
        let selected = currentColor == id
        return Button {
            currentColor = id
        } label: {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 18, height: 18)
                if selected {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.8), lineWidth: 2)
                        .frame(width: 26, height: 26)
                }
            }
            .frame(width: hitSize, height: hitSize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(id)
    }

    private func iconButton(
        _ systemName: String,
        enabled: Bool = true,
        selected: Bool = false,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint ?? (selected ? Color.accentColor : Color.primary))
                .opacity(enabled ? 1 : 0.3)
                .frame(width: hitSize, height: hitSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private struct MarkupCanvas: View {
    @Binding var strokes: [MarkupStroke]
    @Binding var currentTool: String
    @Binding var currentColor: String
    @Binding var currentPoints: [CGPoint]
    var onStrokeEnded: () -> Void

    var body: some View {
        GeometryReader { geo in
            Canvas { context, _ in
                for stroke in strokes {
                    draw(stroke: stroke, in: &context)
                }
                if !currentPoints.isEmpty {
                    let preview = MarkupStroke(
                        tool: currentTool,
                        color: currentColor,
                        points: currentPoints.map { [Double($0.x), Double($0.y)] }
                    )
                    draw(stroke: preview, in: &context)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        currentPoints.append(clamped(value.location, in: geo.size))
                    }
                    .onEnded { _ in
                        guard !currentPoints.isEmpty else { return }
                        let stroke = MarkupStroke(
                            tool: currentTool,
                            color: currentColor,
                            points: currentPoints.map { [Double($0.x), Double($0.y)] }
                        )
                        strokes.append(stroke)
                        currentPoints = []
                        onStrokeEnded()
                    }
            )
        }
    }

    private func clamped(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(0, point.x), size.width),
            y: min(max(0, point.y), size.height)
        )
    }

    private func draw(stroke: MarkupStroke, in context: inout GraphicsContext) {
        let color: Color = switch stroke.color {
        case "green": .green
        case "neutral": Color(white: 0.45)
        default: .red
        }
        let points = stroke.points.compactMap { pair -> CGPoint? in
            guard pair.count == 2 else { return nil }
            return CGPoint(x: pair[0], y: pair[1])
        }
        guard let first = points.first else { return }

        switch stroke.tool {
        case "rect":
            guard let last = points.last else { return }
            let rect = CGRect(
                x: min(first.x, last.x),
                y: min(first.y, last.y),
                width: abs(last.x - first.x),
                height: abs(last.y - first.y)
            )
            context.stroke(Path(rect), with: .color(color), lineWidth: 3)
        case "arrow":
            guard let last = points.last else { return }
            var path = Path()
            path.move(to: first)
            path.addLine(to: last)
            context.stroke(path, with: .color(color), lineWidth: 3)
            let angle = atan2(last.y - first.y, last.x - first.x)
            let head: CGFloat = 14
            var headPath = Path()
            headPath.move(to: last)
            headPath.addLine(to: CGPoint(
                x: last.x - head * cos(angle - .pi / 6),
                y: last.y - head * sin(angle - .pi / 6)
            ))
            headPath.move(to: last)
            headPath.addLine(to: CGPoint(
                x: last.x - head * cos(angle + .pi / 6),
                y: last.y - head * sin(angle + .pi / 6)
            ))
            context.stroke(headPath, with: .color(color), lineWidth: 3)
        default:
            var path = Path()
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            context.stroke(path, with: .color(color), lineWidth: 3)
        }
    }
}

public struct DesignerRootModifier: ViewModifier {
    let screen: String
    let spec: String?
    let context: DesignerContext
    let state: String?
    @ObservedObject private var controller = DesignerModeController.shared

    public func body(content: Content) -> some View {
        content
            .overlay(DesignerModeBanner())
            .overlay {
                if controller.showMarkup {
                    DesignerMarkupView()
                }
            }
            .onAppear {
                DesignerModeController.shared.activate(
                    screen: screen,
                    spec: spec,
                    context: context,
                    state: state
                )
            }
    }
}

private struct DesignerModeBanner: View {
    @ObservedObject private var controller = DesignerModeController.shared
    @ObservedObject private var regions = RegionRegistry.shared

    var body: some View {
        if controller.isDesignerModeActive && !controller.showMarkup {
            VStack(spacing: 8) {
                Text(regions.hasAnnotatedRegions
                     ? "Tap an orange region, or Whole screen"
                     : "No regions tagged · use Whole screen")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.orange)
                    .clipShape(Capsule())

                Button {
                    controller.beginScreenMarkup()
                } label: {
                    Label("Whole screen", systemImage: "rectangle.dashed")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Spacer()
            }
            .padding(.top, 8)
        }
    }
}
#endif
