import SwiftUI
import RedlineShared

/// Unused in the current Mac shell — hierarchy UI is not shown. Kept for optional revive / CLI-adjacent tooling.
/// Layout: toolbar + hierarchy | preview | properties.
struct InspectorWindow: View {
    @ObservedObject var connections: ConnectionManager

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let hierarchy = connections.hierarchy {
                HSplitView {
                    hierarchyPane(hierarchy)
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)

                    HierarchyPreviewView(
                        connections: connections,
                        snapshot: hierarchy
                    )
                    .frame(minWidth: 320)

                    propertiesPane(hierarchy)
                        .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
                }
            } else {
                emptyState
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                connections.scanForApps()
            } label: {
                Label("Scan", systemImage: "arrow.triangle.2.circlepath")
            }

            if !connections.apps.isEmpty {
                Picker("", selection: Binding(
                    get: { connections.selectedApp },
                    set: { app in
                        connections.selectedApp = app
                        Task { await connections.refreshHierarchy() }
                    }
                )) {
                    ForEach(connections.apps) { app in
                        Text("\(app.app.appName) :\(app.port)").tag(Optional(app))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
            }

            Button("Refresh") {
                Task { await connections.refreshHierarchy() }
            }
            .disabled(connections.selectedApp == nil)

            Toggle("Fast", isOn: $connections.fastMode)
                .toggleStyle(.checkbox)
                .onChange(of: connections.fastMode) { _ in
                    Task { await connections.refreshHierarchy() }
                }

            Divider()
                .frame(height: 16)

            Button("Highlight") {
                connections.highlightSelectedNode()
            }
            .disabled(connections.selectedNodeId == nil)

            Button("Redline") {
                connections.redlineSelectedNode()
            }
            .buttonStyle(.borderedProminent)
            .disabled(connections.selectedNodeId == nil)

            Spacer()

            Text(connections.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func hierarchyPane(_ snapshot: HierarchySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Hierarchy")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            Divider()
            List(selection: Binding(
                get: { connections.selectedNodeId },
                set: { nodeId in
                    connections.selectedNodeId = nodeId
                    if let nodeId {
                        Task { await connections.loadAttributes(for: nodeId) }
                    }
                }
            )) {
                ForEach(snapshot.roots, id: \.self) { rootId in
                    if let node = snapshot.nodes[rootId] {
                        HierarchyNodeRow(node: node, snapshot: snapshot)
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func propertiesPane(_ snapshot: HierarchySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Properties")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            Divider()

            if let nodeId = connections.selectedNodeId, let node = snapshot.nodes[nodeId] {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(node.displayName)
                            .font(.headline)
                            .textSelection(.enabled)

                        propertyGroup("Identity") {
                            row("Class", node.className)
                            row("Framework", node.framework)
                            if let region = node.regionName ?? RedlineBridge.resolveRegion(for: nodeId, in: snapshot) {
                                row("Region", region)
                            }
                            row("Path", RedlineBridge.hierarchyPath(for: nodeId, in: snapshot).joined(separator: " › "))
                        }

                        propertyGroup("Layout") {
                            row(
                                "Frame",
                                "\(fmt(node.frame.x)), \(fmt(node.frame.y))  \(fmt(node.frame.w))×\(fmt(node.frame.h))"
                            )
                            row("Hidden", node.isHidden ? "yes" : "no")
                            row("Alpha", String(format: "%.2f", node.alpha))
                            row("Children", "\(node.children.count)")
                        }

                        liveEditGroup
                        measureGroup
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("Select a view")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var liveEditGroup: some View {
        propertyGroup("Live edit") {
            HStack(spacing: 8) {
                Text("Alpha")
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .leading)
                Button("0.5") {
                    Task { await connections.setAttribute(key: "alpha", value: "0.5") }
                }
                Button("1.0") {
                    Task { await connections.setAttribute(key: "alpha", value: "1") }
                }
            }
            .font(.caption)

            Toggle(
                "Hidden",
                isOn: Binding(
                    get: { connections.nodeAttributes?.isHidden ?? false },
                    set: { value in
                        Task {
                            await connections.setAttribute(key: "isHidden", value: value ? "true" : "false")
                        }
                    }
                )
            )
            .font(.caption)
        }
    }

    private var measureGroup: some View {
        propertyGroup("Measure") {
            HStack(spacing: 8) {
                Button("A") { connections.setMeasureFromSelected() }
                Button("B") { connections.setMeasureToSelected() }
                Button("Gap") {
                    Task { await connections.runMeasure() }
                }
                .buttonStyle(.borderedProminent)
            }
            .font(.caption)
            .disabled(connections.selectedNodeId == nil)

            row("A", connections.measureFromNodeId ?? "—")
            row("B", connections.measureToNodeId ?? "—")
            if let gap = connections.lastMeasuredGap {
                row("Result", String(format: "dx %.1f  dy %.1f", gap.dx, gap.dy))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "iphone")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No app connected")
                .font(.title3.weight(.medium))
            Text("Run your app in Simulator with RedlineServer, then Scan.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button("Scan for Apps") {
                connections.scanForApps()
            }
            .buttonStyle(.borderedProminent)
            if !connections.statusMessage.isEmpty {
                Text(connections.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func propertyGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
    }

    private func fmt(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

private struct HierarchyNodeRow: View {
    let node: HierarchyNode
    let snapshot: HierarchySnapshot

    var body: some View {
        if node.children.isEmpty {
            label.tag(node.id)
        } else {
            DisclosureGroup {
                ForEach(node.children, id: \.self) { childId in
                    if let child = snapshot.nodes[childId] {
                        HierarchyNodeRow(node: child, snapshot: snapshot)
                    }
                }
            } label: {
                label
            }
            .tag(node.id)
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            if node.regionName != nil {
                Circle()
                    .fill(.orange)
                    .frame(width: 6, height: 6)
            }
            Text(node.displayName)
                .lineLimit(1)
            if node.isHidden {
                Text("hidden")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
    }
}
