import Combine
import SwiftUI
import RedlineShared

@MainActor
final class AppModel: ObservableObject {
    let inbox = InboxStore()
    let settingsStore = AgentSettingsStore()
    let agentRunner = AgentRunner()
    let receiverSettings = ReceiverSettingsSnapshot()

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
            }
            .store(in: &cancellables)
        // Do not relay settingsStore → AppModel: mode/settings edits were re-rendering the
        // whole window (and eating clicks). RootWindow observes settingsStore directly.
    }

    func start() {
        guard server == nil else { return }
        receiverSettings.update(from: settingsStore.settings)

        let snapshot = receiverSettings
        let server = FeedbackHTTPServer(
            authToken: { snapshot.token() },
            maxBodyBytes: { snapshot.bodyLimit() },
            inboxProvider: { [weak self] in
                guard let self else { return nil }
                var data: Data?
                if Thread.isMainThread {
                    data = MainActor.assumeIsolated {
                        try? self.inbox.inboxJSON()
                    }
                } else {
                    DispatchQueue.main.sync {
                        data = MainActor.assumeIsolated {
                            try? self.inbox.inboxJSON()
                        }
                    }
                }
                return data
            },
            inboxStatusHandler: { [weak self] id, statusRaw, summary in
                guard let self else {
                    return (503, "{\"ok\":false,\"error\":\"App not ready\"}")
                }
                var payload = (ok: false, error: "Unknown error", status: statusRaw)
                let apply: () -> Void = {
                    let status = InboxItem.Status.fromPersisted(statusRaw)
                    let allowed: Set<String> = ["pending", "agent_running", "applied", "failed"]
                    guard allowed.contains(status.rawValue) || allowed.contains(statusRaw) else {
                        payload = (false, "Invalid status '\(statusRaw)' — use pending|agent_running|applied|failed", statusRaw)
                        return
                    }
                    // Normalize aliases (e.g. finished → applied is not mapped; accept finished as applied)
                    let resolved: InboxItem.Status
                    switch statusRaw.lowercased() {
                    case "finished", "done", "applied": resolved = .applied
                    case "running", "agent_running", "in_progress": resolved = .agentRunning
                    case "failed", "error": resolved = .failed
                    case "pending", "open": resolved = .pending
                    default: resolved = status
                    }
                    let result = MainActor.assumeIsolated { () -> (Bool, String) in
                        let ok = self.inbox.setStatusFromAgent(id: id, status: resolved, summary: summary)
                        return (ok, self.inbox.lastError ?? "Update failed")
                    }
                    if result.0 {
                        payload = (true, "", resolved.rawValue)
                    } else {
                        payload = (false, result.1, resolved.rawValue)
                    }
                }
                if Thread.isMainThread {
                    apply()
                } else {
                    DispatchQueue.main.sync(execute: apply)
                }
                if payload.ok {
                    return (200, "{\"ok\":true,\"id\":\"\(id)\",\"status\":\"\(payload.status)\"}")
                }
                let err = payload.error.replacingOccurrences(of: "\"", with: "'")
                return (404, "{\"ok\":false,\"error\":\"\(err)\"}")
            }
        ) { [weak self] payload in
            guard let self else { return }
            await MainActor.run {
                self.receiverSettings.update(from: self.settingsStore.settings)
            }
            let item = await self.inbox.receive(payload, settings: self.settingsStore.settings)
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
            receiverStatus = "Listening on :\(RedlinePorts.feedbackDefault)"
        } catch {
            receiverStatus = "Receiver failed: \(error.localizedDescription)"
        }
    }

    func settingsDidChange() {
        receiverSettings.update(from: settingsStore.settings)
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
