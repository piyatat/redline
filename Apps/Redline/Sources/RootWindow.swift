import SwiftUI
import RedlineShared

enum AppPane: String, CaseIterable, Identifiable {
    case inbox
    case settings

    var id: String { rawValue }
}

struct RootWindow: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settingsStore: AgentSettingsStore
    @State private var pane: AppPane = .inbox

    init(model: AppModel) {
        self.model = model
        self.settingsStore = model.settingsStore
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            // Keep Inbox mounted so split-pane sizes survive Settings navigation.
            ZStack {
                InboxPanelView(
                    inbox: model.inbox,
                    settingsStore: settingsStore,
                    agentRunner: model.agentRunner
                )
                .opacity(pane == .inbox ? 1 : 0)
                .allowsHitTesting(pane == .inbox)
                .accessibilityHidden(pane != .inbox)

                if pane == .settings {
                    AgentSettingsPanelView(settingsStore: settingsStore)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .redlineAppTypography(fontSizePoints: settingsStore.settings.logFontSize)
        .appFont(.body)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            if pane == .settings {
                Button {
                    pane = .inbox
                } label: {
                    Label("Inbox", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                .help("Back to Inbox")

                Text("Settings")
                    .appFont(.body, weight: .semibold)
            } else {
                Label("Inbox", systemImage: "tray.full")
                    .appFont(.body, weight: .semibold)
                    .foregroundStyle(.primary)

                if !model.inbox.items.isEmpty {
                    Text("\(model.inbox.items.count)")
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            Spacer(minLength: 12)

            if !model.agentRunner.lastMessage.isEmpty {
                Text(model.agentRunner.lastMessage)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(model.receiverStatus)
                .appFont(.caption, design: .monospaced)
                .foregroundStyle(.secondary)

            Button {
                pane = pane == .settings ? .inbox : .settings
            } label: {
                Image(systemName: pane == .settings ? "gearshape.fill" : "gearshape")
                    .appFont(.title3)
                    .foregroundStyle(pane == .settings ? Color.accentColor : Color.secondary)
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(pane == .settings ? "Close Settings" : "Settings")
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onReceive(NotificationCenter.default.publisher(for: .redlineShowInbox)) { _ in
            pane = .inbox
        }
    }
}
