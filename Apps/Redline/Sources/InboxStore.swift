import Foundation
import RedlineShared

/// Lightweight on-disk inbox index (payload lives in each bundle’s feedback.json).
private struct PersistedInboxRecord: Codable, Equatable {
    var id: String
    var receivedAt: Date
    var status: InboxItem.Status
    var bundleDirectory: String?
    var proposalSummary: String?
    var proposalDiffPath: String?
}

@MainActor
final class InboxStore: ObservableObject {
    @Published private(set) var items: [InboxItem] = []
    @Published var lastError: String?

    private let supportDirectory: URL
    private let indexURL: URL
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init() {
        supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Redline", isDirectory: true)
        indexURL = supportDirectory.appendingPathComponent("inbox-index.json")
        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        loadPersisted()
    }

    /// Persists a feedback bundle. On write failure, inserts a `.failed` inbox row for visibility, then **throws** so the HTTP receiver can return non-2xx (devices keep markup open).
    func receive(_ payload: FeedbackPayload, settings: AgentSettings) async throws -> InboxItem {
        let itemId = UUID().uuidString
        var item = InboxItem(id: itemId, payload: payload)
        _ = settings

        do {
            // Always write under Application Support/Redline/feedback — no workspace setting.
            let bundleDir = try FeedbackBundleWriter.write(
                payload: payload,
                itemId: itemId,
                workspaceRoot: nil,
                supportDirectory: supportDirectory
            )
            item.bundleDirectory = bundleDir.path
            items.insert(item, at: 0)
            persist()
            return item
        } catch {
            lastError = error.localizedDescription
            item.status = .failed
            item.proposalSummary = "Bundle write failed: \(error.localizedDescription)"
            items.insert(item, at: 0)
            persist()
            throw error
        }
    }

    func updateStatus(id: String, status: InboxItem.Status, proposalSummary: String? = nil) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = status
        if let proposalSummary {
            items[index].proposalSummary = proposalSummary
        }
        persist()
    }

    /// User-driven status change. Cannot mark as running (that is agent-owned).
    @discardableResult
    func setStatusManually(id: String, status: InboxItem.Status) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        guard status != .agentRunning else {
            lastError = "Can’t mark as running manually"
            return false
        }
        guard InboxItem.Status.manuallyAssignable.contains(status) else { return false }
        guard items[index].status != status else { return true }
        items[index].status = status
        // Preserve agent/MCP summaries; only stamp a note when none exists.
        if items[index].proposalSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            items[index].proposalSummary = "Status set manually to \(status.displayName)"
        }
        lastError = nil
        persist()
        return true
    }

    /// Status update from MCP / HTTP (Cursor desktop agent). Allows `agent_running`.
    @discardableResult
    func setStatusFromAgent(id: String, status: InboxItem.Status, summary: String?) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            lastError = "Inbox item not found"
            return false
        }
        let current = items[index].status
        if status == .agentRunning {
            // True CAS: only pending → agent_running. Already-running is a conflict (409),
            // so a second waiter/owner cannot treat HTTP 200 as ownership.
            guard current == .pending else {
                lastError = current == .agentRunning
                    ? "Already claimed (agent_running)"
                    : "Cannot claim \(current.rawValue) item as agent_running"
                return false
            }
        }

        items[index].status = status
        let trimmed = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            items[index].proposalSummary = trimmed
        } else if items[index].proposalSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            switch status {
            case .agentRunning:
                items[index].proposalSummary = "Cursor MCP agent working…"
            case .applied:
                items[index].proposalSummary = "Finished via Cursor MCP"
            case .failed:
                items[index].proposalSummary = "Failed via Cursor MCP"
            case .pending:
                items[index].proposalSummary = "Returned to pending via Cursor MCP"
            }
        }
        lastError = nil
        persist()
        return true
    }

    /// Local CLI claim — CAS `pending → agent_running`. Returns false if already claimed.
    @discardableResult
    func claimPendingAsRunning(id: String, summary: String) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            lastError = "Inbox item not found"
            return false
        }
        guard items[index].status == .pending else {
            lastError = "Item is \(items[index].status.rawValue) — cannot claim"
            return false
        }
        items[index].status = .agentRunning
        items[index].proposalSummary = summary
        lastError = nil
        persist()
        return true
    }

    /// Update editable feedback fields and rewrite bundle `feedback.json` + `prompt.md`.
    @discardableResult
    func updateFeedback(
        id: String,
        screen: String,
        region: String,
        comment: String,
        state: String?,
        spec: String?
    ) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        guard items[index].status != .agentRunning else {
            lastError = "Can’t edit while the agent is running"
            return false
        }

        var payload = items[index].payload
        payload.screen = screen.trimmingCharacters(in: .whitespacesAndNewlines)
        payload.region = region.trimmingCharacters(in: .whitespacesAndNewlines)
        payload.comment = comment
        let trimmedState = state?.trimmingCharacters(in: .whitespacesAndNewlines)
        payload.state = (trimmedState?.isEmpty == false) ? trimmedState : nil
        let trimmedSpec = spec?.trimmingCharacters(in: .whitespacesAndNewlines)
        payload.spec = (trimmedSpec?.isEmpty == false) ? trimmedSpec : nil

        items[index].payload = payload
        // Editing means it needs another agent pass.
        if items[index].status == .applied {
            items[index].status = .pending
        }

        if let path = items[index].bundleDirectory {
            let bundle = URL(fileURLWithPath: path).standardizedFileURL
            guard isBundlePathSafe(bundle) else {
                lastError = "Refusing to write outside feedback directory"
                persist()
                return true
            }
            do {
                try payload.encode().write(to: bundle.appendingPathComponent("feedback.json"), options: .atomic)
                let prompt = AgentPromptBuilder().makePrompt(for: payload, bundleDirectory: bundle)
                try prompt.data(using: .utf8)?.write(
                    to: bundle.appendingPathComponent("prompt.md"),
                    options: .atomic
                )
            } catch {
                lastError = "Saved in inbox, but bundle update failed: \(error.localizedDescription)"
            }
        }

        persist()
        return true
    }

    /// Remove from inbox and delete the on-disk feedback bundle.
    @discardableResult
    func remove(id: String, deleteBundle: Bool = true) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        guard items[index].status != .agentRunning else {
            lastError = "Can’t remove while the agent is running"
            return false
        }

        let bundlePath = items[index].bundleDirectory
        items.remove(at: index)
        persist()

        if deleteBundle, let bundlePath {
            let url = URL(fileURLWithPath: bundlePath).standardizedFileURL
            if isBundlePathSafe(url) {
                try? FileManager.default.removeItem(at: url)
            } else {
                lastError = "Skipped deleting bundle outside feedback directory"
            }
        }
        return true
    }

    /// Applied / finished feedback count.
    var finishedCount: Int {
        items.filter { Self.isFinished($0.status) }.count
    }

    /// Remove all finished (applied) items and optionally delete their bundles.
    @discardableResult
    func removeFinished(deleteBundles: Bool = true) -> Int {
        let finished = items.filter { Self.isFinished($0.status) }
        guard !finished.isEmpty else { return 0 }

        let ids = Set(finished.map(\.id))
        let paths = finished.compactMap(\.bundleDirectory)

        items.removeAll { ids.contains($0.id) }
        persist()

        if deleteBundles {
            for path in paths {
                let url = URL(fileURLWithPath: path).standardizedFileURL
                guard isBundlePathSafe(url) else { continue }
                try? FileManager.default.removeItem(at: url)
            }
        }
        return finished.count
    }

    private func isBundlePathSafe(_ url: URL) -> Bool {
        let feedbackRoot = supportDirectory
            .appendingPathComponent("feedback", isDirectory: true)
            .standardizedFileURL
        let child = url.standardizedFileURL.path
        let parent = feedbackRoot.path
        if child == parent { return true }
        let prefix = parent.hasSuffix("/") ? parent : parent + "/"
        return child.hasPrefix(prefix)
    }

    func item(id: String) -> InboxItem? {
        items.first { $0.id == id }
    }

    /// Slim list for `GET /inbox` — omits `compositePngBase64` (use bundle on disk for pixels).
    func inboxJSON() throws -> Data {
        let snaps = items.map { InboxItemMCPSnapshot(from: $0, stagedFeedbackPath: nil) }
        return try encoder.encode(snaps)
    }

    /// Finished = successfully applied. Everything else stays as open/history work.
    nonisolated static func isFinished(_ status: InboxItem.Status) -> Bool {
        status == .applied
    }

    nonisolated static func isOpenWork(_ status: InboxItem.Status) -> Bool {
        !isFinished(status)
    }

    private func persist() {
        // Persist every item (including applied/finished) for the next session.
        let records: [PersistedInboxRecord] = items.map { item in
            PersistedInboxRecord(
                id: item.id,
                receivedAt: item.receivedAt,
                status: item.status,
                bundleDirectory: item.bundleDirectory,
                proposalSummary: item.proposalSummary,
                proposalDiffPath: item.proposalDiffPath
            )
        }
        do {
            try encoder.encode(records).write(to: indexURL, options: .atomic)
        } catch {
            lastError = "Failed to save inbox: \(error.localizedDescription)"
        }
    }

    private func loadPersisted() {
        var loaded: [InboxItem] = []

        if let data = try? Data(contentsOf: indexURL),
           let records = try? decoder.decode([PersistedInboxRecord].self, from: data) {
            for record in records {
                // Restore all statuses, including applied/finished.
                guard let item = hydrate(record) else { continue }
                loaded.append(item)
            }
        }

        // Recover bundles that never made it into the index (crash before persist, older builds).
        let knownBundles = Set(loaded.compactMap(\.bundleDirectory))
        for orphan in discoverOrphanBundles(excluding: knownBundles) {
            loaded.append(orphan)
        }

        loaded.sort { $0.receivedAt > $1.receivedAt }
        items = loaded
        if !loaded.isEmpty {
            persist()
        }
    }

    private func hydrate(_ record: PersistedInboxRecord) -> InboxItem? {
        guard let path = record.bundleDirectory,
              FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        let bundle = URL(fileURLWithPath: path)
        guard let payload = loadPayload(from: bundle) else { return nil }

        var status = record.status
        var summary = record.proposalSummary
        // Process was killed with the app — not actually running anymore.
        if status == .agentRunning {
            status = .pending
            let note = "Interrupted last session — retry via Send to AI or /redline-wait"
            if let existing = summary, !existing.isEmpty {
                summary = "\(note)\n\(existing)"
            } else {
                summary = note
            }
        }

        return InboxItem(
            id: record.id,
            receivedAt: record.receivedAt,
            status: status,
            payload: payload,
            bundleDirectory: path,
            proposalSummary: summary,
            proposalDiffPath: record.proposalDiffPath
        )
    }

    private func loadPayload(from bundle: URL) -> FeedbackPayload? {
        let jsonURL = bundle.appendingPathComponent("feedback.json")
        guard let data = try? Data(contentsOf: jsonURL),
              var payload = try? FeedbackPayload.decode(from: data) else {
            return nil
        }
        // Prefer PNG file if base64 missing/empty in JSON.
        if payload.compositePngBase64.isEmpty {
            let pngURL = bundle.appendingPathComponent("composite.png")
            if let png = try? Data(contentsOf: pngURL) {
                payload.compositePngBase64 = png.base64EncodedString()
            }
        }
        return payload
    }

    private func discoverOrphanBundles(excluding known: Set<String>) -> [InboxItem] {
        let feedbackRoot = supportDirectory.appendingPathComponent("feedback", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: feedbackRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var orphans: [InboxItem] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent == "feedback.json" else { continue }
            let bundle = url.deletingLastPathComponent()
            let path = bundle.path
            guard !known.contains(path) else { continue }
            guard let payload = loadPayload(from: bundle) else { continue }

            let id = bundle.lastPathComponent
            let receivedAt = (try? bundle.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            orphans.append(
                InboxItem(
                    id: id,
                    receivedAt: receivedAt,
                    status: .pending,
                    payload: payload,
                    bundleDirectory: path,
                    proposalSummary: "Restored from disk — not finished"
                )
            )
        }
        return orphans
    }
}
