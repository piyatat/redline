import Combine
import Foundation
import SwiftUI
import RedlineShared

/// Thread-safe inbox JSON snapshot for the HTTP receiver (avoids `main.sync` from the Network queue).
final class InboxJSONCache: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data = Data("[]".utf8)

    func update(_ newData: Data) {
        lock.lock()
        data = newData
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

@MainActor
final class AppModel: ObservableObject {
    let inbox = InboxStore()
    let settingsStore = AgentSettingsStore()
    let agentRunner = AgentRunner()
    let receiverSettings = ReceiverSettingsSnapshot()
    private let inboxJSONCache = InboxJSONCache()

    @Published var receiverStatus = "Starting…"

    private var server: FeedbackHTTPServer?
    private var cancellables = Set<AnyCancellable>()

    init() {
        agentRunner.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        inbox.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.refreshInboxJSONCache()
            }
            .store(in: &cancellables)
    }
    // Do not relay settingsStore → AppModel: mode/settings edits were re-rendering the
    // whole window (and eating clicks). RootWindow observes settingsStore directly.

    func start() {
        guard server == nil else { return }
        receiverSettings.update(from: settingsStore.settings)
        refreshInboxJSONCache()

        let snapshot = receiverSettings
        let inboxCache = inboxJSONCache
        let server = FeedbackHTTPServer(
            authToken: { snapshot.token() },
            maxBodyBytes: { snapshot.bodyLimit() },
            inboxProvider: {
                inboxCache.snapshot()
            },
            inboxStatusHandler: { [weak self] id, statusRaw, summary in
                guard let self else {
                    return (503, RedlineJSON.object(["ok": false, "error": "App not ready"]))
                }
                return await MainActor.run {
                    guard let resolved = InboxItem.Status.parseAgentStatus(statusRaw) else {
                        return (
                            422,
                            RedlineJSON.object([
                                "ok": false,
                                "error": "Invalid status '\(statusRaw)' — use pending|agent_running|applied|failed",
                            ])
                        )
                    }
                    let ok = self.inbox.setStatusFromAgent(id: id, status: resolved, summary: summary)
                    if ok {
                        self.agentRunner.noteExternalStatus(
                            id: id,
                            status: resolved.rawValue,
                            summary: summary
                        )
                        self.refreshInboxJSONCache()
                        return (
                            200,
                            RedlineJSON.object([
                                "ok": true,
                                "id": id,
                                "status": resolved.rawValue,
                            ])
                        )
                    }
                    let err = self.inbox.lastError ?? "Update failed"
                    let code = err.contains("not found") ? 404 : 409
                    return (code, RedlineJSON.object(["ok": false, "error": err]))
                }
            }
        ) { [weak self] payload in
            guard let self else {
                throw InboxReceiveError.appNotReady
            }
            await MainActor.run {
                self.receiverSettings.update(from: self.settingsStore.settings)
            }
            let item = try await self.inbox.receive(payload, settings: self.settingsStore.settings)
            await MainActor.run {
                self.refreshInboxJSONCache()
            }
            // Respond to iOS immediately — do not wait for the agent run (can take minutes).
            Task { @MainActor in
                await self.agentRunner.handleNewFeedback(
                    item: item,
                    settings: self.settingsStore.settings,
                    inbox: self.inbox
                )
            }
        }
        do {
            try server.start()
            self.server = server
            receiverStatus = "Listening on 127.0.0.1:\(RedlinePorts.feedbackDefault)"
        } catch {
            receiverStatus = "Receiver failed: \(error.localizedDescription)"
        }
    }

    func settingsDidChange() {
        receiverSettings.update(from: settingsStore.settings)
    }

    private func refreshInboxJSONCache() {
        let data = (try? inbox.inboxJSON()) ?? Data("[]".utf8)
        inboxJSONCache.update(data)
    }
}

private enum InboxReceiveError: Error, LocalizedError {
    case appNotReady

    var errorDescription: String? {
        switch self {
        case .appNotReady: return "App not ready"
        }
    }
}

private enum RedlineJSON {
    static func object(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{\"ok\":false,\"error\":\"encode failed\"}"
        }
        return text
    }
}

@main
struct RedlineApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootWindow(model: model)
                .frame(minWidth: 900, minHeight: 560)
                .onAppear { model.start() }
                .onChange(of: model.settingsStore.settings) { _ in
                    model.settingsDidChange()
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Inbox") {
                Button("Show Inbox") {
                    NotificationCenter.default.post(name: .redlineShowInbox, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
        }
    }
}

extension Notification.Name {
    static let redlineShowInbox = Notification.Name("dev.redline.showInbox")
}
