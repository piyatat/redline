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
                    return (503, RedlineJSON.object(["ok": false, "error": "App not ready"]))
                }
                var httpStatus = 500
                var body = RedlineJSON.object(["ok": false, "error": "Unknown error"])
                let apply: () -> Void = {
                    guard let resolved = InboxItem.Status.parseAgentStatus(statusRaw) else {
                        httpStatus = 422
                        body = RedlineJSON.object([
                            "ok": false,
                            "error": "Invalid status '\(statusRaw)' — use pending|agent_running|applied|failed",
                        ])
                        return
                    }
                    let result = MainActor.assumeIsolated { () -> (Bool, String) in
                        let ok = self.inbox.setStatusFromAgent(id: id, status: resolved, summary: summary)
                        return (ok, self.inbox.lastError ?? "Update failed")
                    }
                    if result.0 {
                        httpStatus = 200
                        body = RedlineJSON.object([
                            "ok": true,
                            "id": id,
                            "status": resolved.rawValue,
                        ])
                        MainActor.assumeIsolated {
                            self.agentRunner.noteExternalStatus(
                                id: id,
                                status: resolved.rawValue,
                                summary: summary
                            )
                        }
                    } else {
                        httpStatus = result.1.contains("not found") ? 404 : 409
                        body = RedlineJSON.object(["ok": false, "error": result.1])
                    }
                }
                if Thread.isMainThread {
                    apply()
                } else {
                    DispatchQueue.main.sync(execute: apply)
                }
                return (httpStatus, body)
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
            receiverStatus = "Listening on 127.0.0.1:\(RedlinePorts.feedbackDefault)"
        } catch {
            receiverStatus = "Receiver failed: \(error.localizedDescription)"
        }
    }

    func settingsDidChange() {
        receiverSettings.update(from: settingsStore.settings)
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
