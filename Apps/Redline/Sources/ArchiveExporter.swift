import Foundation
import RedlineShared

enum ArchiveExporter {
    static func export(
        hierarchy: HierarchySnapshot,
        client: InspectorClient,
        port: UInt16,
        screenshotNodeIds: [String]
    ) async -> URL? {
        let exportsRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Redline/exports", isDirectory: true)
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let archiveDir = exportsRoot
            .appendingPathComponent("\(hierarchy.app.appName)-\(timestamp).redline", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: archiveDir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(hierarchy).write(to: archiveDir.appendingPathComponent("hierarchy.json"))

            let manifest = RedlineArchiveManifest(
                exportedAt: ISO8601DateFormatter().string(from: Date()),
                app: hierarchy.app,
                nodeCount: hierarchy.nodes.count,
                screenshotNodeIds: screenshotNodeIds
            )
            try encoder.encode(manifest).write(to: archiveDir.appendingPathComponent("manifest.json"))

            let shotsDir = archiveDir.appendingPathComponent("screenshots", isDirectory: true)
            try FileManager.default.createDirectory(at: shotsDir, withIntermediateDirectories: true)
            for nodeId in screenshotNodeIds {
                if let png = try? await client.snapshotPNGBase64(nodeId: nodeId, port: port),
                   let data = Data(base64Encoded: png) {
                    try data.write(to: shotsDir.appendingPathComponent("\(nodeId).png"))
                }
            }
            return archiveDir
        } catch {
            fputs("Archive export failed: \(error)\n", stderr)
            return nil
        }
    }
}
