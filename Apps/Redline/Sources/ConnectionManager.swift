import AppKit
import Foundation
import RedlineShared

@MainActor
final class ConnectionManager: ObservableObject {
    @Published var apps: [DiscoveredApp] = []
    @Published var selectedApp: DiscoveredApp?
    @Published var hierarchy: HierarchySnapshot?
    @Published var selectedNodeId: String?
    @Published var nodeAttributes: NodeAttributes?
    @Published var measureFromNodeId: String?
    @Published var measureToNodeId: String?
    @Published var lastMeasuredGap: MeasuredGap?
    @Published var measuredGaps: [MeasuredGap] = []
    @Published var statusMessage = "Scan to find Simulator apps"
    @Published var fastMode = false
    @Published var previewImage: NSImage?
    @Published var previewImageError: String?

    private let client = InspectorClient()

    var captureOptions: HierarchyCaptureOptions {
        fastMode ? .fast : .default
    }

    func scanForApps() {
        statusMessage = "Scanning…"
        let client = self.client
        Task.detached(priority: .userInitiated) {
            var found: [DiscoveredApp] = []
            var openPortHints: [String] = []

            for port in RedlinePorts.simulatorInspectStart ... RedlinePorts.simulatorInspectEnd {
                do {
                    let app = try await client.ping(port: UInt16(port))
                    found.append(DiscoveredApp(host: "127.0.0.1", port: UInt16(port), app: app, connectionKind: .simulator))
                } catch {
                    if port == RedlinePorts.simulatorInspectStart {
                        openPortHints.append("47164: \(error.localizedDescription)")
                    }
                }
            }

            for port in RedlinePorts.usbInspectStart ... RedlinePorts.usbInspectEnd {
                if let app = try? await client.ping(port: UInt16(port)) {
                    found.append(DiscoveredApp(host: "127.0.0.1", port: UInt16(port), app: app, connectionKind: .usb))
                }
            }

            // Capture locals before hopping to MainActor (Swift 6: no mutable capture across isolation).
            let discovered = found
            let hints = openPortHints
            await MainActor.run {
                self.apps = discovered
                if self.selectedApp == nil || !discovered.contains(where: { $0.id == self.selectedApp?.id }) {
                    self.selectedApp = discovered.first
                }
                if discovered.isEmpty {
                    let hint = hints.first.map { " (\($0))" } ?? ""
                    self.statusMessage = "No apps found\(hint)"
                } else {
                    self.statusMessage = "Found \(discovered.count)"
                }
            }

            let hasSelection = await MainActor.run { self.selectedApp != nil }
            if hasSelection {
                await self.refreshHierarchy()
            }
        }
    }

    func refreshHierarchy() async {
        guard let app = selectedApp else { return }
        statusMessage = "Refreshing…"
        do {
            hierarchy = try await client.fetchHierarchy(port: app.port, options: captureOptions)
            statusMessage = "\(app.app.appName) · \(app.port)"
            await refreshPreviewImage()
            if let nodeId = selectedNodeId {
                await loadAttributes(for: nodeId)
            } else if let root = hierarchy?.roots.first {
                selectedNodeId = root
                await loadAttributes(for: root)
            }
        } catch {
            statusMessage = "Refresh failed: \(error.localizedDescription)"
        }
    }

    func refreshPreviewImage() async {
        guard let app = selectedApp, let rootId = hierarchy?.roots.first else {
            previewImage = nil
            return
        }
        do {
            let b64 = try await client.snapshotPNGBase64(nodeId: rootId, port: app.port)
            guard let data = Data(base64Encoded: b64), let image = NSImage(data: data) else {
                previewImage = nil
                previewImageError = "Invalid screenshot data"
                return
            }
            previewImage = image
            previewImageError = nil
        } catch {
            previewImage = nil
            previewImageError = error.localizedDescription
        }
    }

    /// Per-view snapshot for 3D layers (not a window crop).
    func fetchNodeSnapshot(nodeId: String) async -> NSImage? {
        guard let app = selectedApp else { return nil }
        do {
            let b64 = try await client.snapshotPNGBase64(nodeId: nodeId, port: app.port)
            guard let data = Data(base64Encoded: b64) else { return nil }
            return NSImage(data: data)
        } catch {
            return nil
        }
    }

    func refreshSelectedNode() async {
        guard let app = selectedApp, let nodeId = selectedNodeId else { return }
        do {
            _ = try await client.refreshNode(nodeId: nodeId, port: app.port, options: captureOptions)
            await refreshHierarchy()
        } catch {
            statusMessage = "Node refresh failed: \(error.localizedDescription)"
        }
    }

    func loadAttributes(for nodeId: String) async {
        guard let app = selectedApp else { return }
        nodeAttributes = try? await client.fetchAttributes(nodeId: nodeId, port: app.port)
    }

    func setAttribute(key: String, value: String) async {
        guard let app = selectedApp, let nodeId = selectedNodeId else { return }
        do {
            try await client.setAttribute(nodeId: nodeId, key: key, value: value, port: app.port)
            await loadAttributes(for: nodeId)
            await refreshHierarchy()
        } catch {
            statusMessage = "Edit failed: \(error.localizedDescription)"
        }
    }

    func setMeasureFromSelected() {
        measureFromNodeId = selectedNodeId
    }

    func setMeasureToSelected() {
        measureToNodeId = selectedNodeId
    }

    func runMeasure() async {
        guard let app = selectedApp,
              let from = measureFromNodeId,
              let to = measureToNodeId else {
            statusMessage = "Set A and B first"
            return
        }
        do {
            let gap = try await client.measure(from: from, to: to, port: app.port)
            lastMeasuredGap = gap
            measuredGaps.append(gap)
            statusMessage = String(format: "Gap dx=%.1f dy=%.1f", gap.dx, gap.dy)
        } catch {
            statusMessage = "Measure failed: \(error.localizedDescription)"
        }
    }

    func highlightSelectedNode() {
        guard let app = selectedApp, let nodeId = selectedNodeId else { return }
        Task { try? await client.highlight(nodeId: nodeId, port: app.port) }
    }

    func redlineSelectedNode(pins: [DesignerPin] = []) {
        guard let app = selectedApp, let nodeId = selectedNodeId, let hierarchy else { return }
        let bridge = RedlineBridge.buildStartPayload(
            nodeId: nodeId,
            in: hierarchy,
            measuredGaps: measuredGaps,
            pins: pins
        )
        Task {
            do {
                try await client.startRedline(bridge: bridge, port: app.port)
                statusMessage = "Redline opened · \(bridge.region)"
            } catch {
                statusMessage = "Redline failed: \(error.localizedDescription)"
            }
        }
    }

    func exportArchive() async -> URL? {
        guard let app = selectedApp, let hierarchy else { return nil }
        return await ArchiveExporter.export(
            hierarchy: hierarchy,
            client: client,
            port: app.port,
            screenshotNodeIds: Array(Set([selectedNodeId].compactMap { $0 }))
        )
    }
}
