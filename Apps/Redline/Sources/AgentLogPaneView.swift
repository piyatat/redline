import AppKit
import SwiftUI
import RedlineShared

/// Bottom pane: agent stdout/stderr + chat input for follow-ups.
struct AgentLogPaneView: View {
    @ObservedObject var agentRunner: AgentRunner
    @ObservedObject var settingsStore: AgentSettingsStore
    @ObservedObject var inbox: InboxStore
    var selectedItem: InboxItem?

    @Environment(\.appFontSize) private var appFontSize

    @State private var draft = ""
    @State private var copiedFlash = false

    private var logFont: Font {
        .system(size: appFontSize, design: .monospaced)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            logBody
            Divider()
            inputBar
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: agentRunner.isBusy ? "ellipsis.circle" : "terminal")
                .foregroundStyle(agentRunner.isBusy ? Color.accentColor : .secondary)

            Text(title)
                .appFont(.headline)

            if agentRunner.isBusy {
                ProgressView()
                    .controlSize(.small)

                Button {
                    agentRunner.stop(inbox: inbox)
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
                .help("Stop the running agent")
            } else if agentRunner.canContinueSession {
                Text("session")
                    .appFont(.caption, weight: .semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
                    .help("Follow-ups continue the last agent session in this project")
            }

            Spacer()

            Button {
                agentRunner.resetSession()
            } label: {
                Label("New session", systemImage: "plus.bubble")
            }
            .buttonStyle(.borderless)
            .disabled(agentRunner.isBusy || !agentRunner.canContinueSession)
            .help("Start a fresh agent session (next message won’t --continue)")

            Button {
                copyLog()
            } label: {
                Label(copiedFlash ? "Copied" : "Copy", systemImage: copiedFlash ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .disabled(displayText.isEmpty)
            .help("Copy agent output to clipboard")

            Button {
                agentRunner.clearLog()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(displayText.isEmpty || agentRunner.isBusy)
            .help("Clear the log pane")
        }
        .appFont(.body)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var title: String {
        if agentRunner.isBusy {
            let seconds = agentRunner.runElapsedSeconds
            return seconds > 0 ? "Agent — running… \(seconds)s" : "Agent — running…"
        }
        if displayText.isEmpty {
            return "Agent"
        }
        return "Agent — ready"
    }

    private var displayText: String {
        agentRunner.agentLog
    }

    private var chatEnabled: Bool {
        // Desktop MCP mode — keep local CLI chat off to avoid fighting Cursor.
        if settingsStore.settings.onNewFeedback == .awaitDesktopMCP {
            return false
        }
        switch settingsStore.settings.agentBackend {
        case .cursorCLI, .claudeCLI: return true
        case .shellHook: return false
        }
    }

    @ViewBuilder
    private var logBody: some View {
        if displayText.isEmpty {
            Text(emptyHint)
                .appFont(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(displayText)
                        .font(logFont)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .id("log-end")
                }
                .onChange(of: displayText) { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("log-end", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .center, spacing: 8) {
            TextField(placeholder, text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(logFont)
                .disabled(!chatEnabled || agentRunner.isBusy)
                .onSubmit { send() }

            if agentRunner.isBusy {
                Button("Stop", role: .destructive) {
                    agentRunner.stop(inbox: inbox)
                }
            } else {
                Button("Send") { send() }
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(!canSend)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var placeholder: String {
        if settingsStore.settings.onNewFeedback == .awaitDesktopMCP {
            return "Chat disabled in MCP mode — use /redline-wait in Cursor…"
        }
        if !chatEnabled {
            return "Switch backend in Settings to Cursor or Claude to chat…"
        }
        if agentRunner.isBusy {
            return "Waiting for agent…"
        }
        if agentRunner.canContinueSession {
            return "Follow-up message…"
        }
        return "Message the agent…"
    }

    private var canSend: Bool {
        chatEnabled
            && !agentRunner.isBusy
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var emptyHint: String {
        if agentRunner.isBusy {
            return "Waiting for agent output…"
        }
        if settingsStore.settings.onNewFeedback == .awaitDesktopMCP {
            return "Desktop MCP mode — agent work happens in Cursor via `/redline-wait`. Status updates from MCP appear here."
        }
        if chatEnabled {
            return "Send to AI from an inbox item, or type a message below to talk to the agent in your project folder."
        }
        return "Agent stdout/stderr appears here. Interactive chat requires Cursor Agent CLI or Claude Code CLI."
    }

    private func send() {
        let text = draft
        guard canSend else { return }
        draft = ""
        Task {
            await agentRunner.sendChat(
                message: text,
                settings: settingsStore.settings,
                inbox: inbox,
                item: selectedItem
            )
        }
    }

    private func copyLog() {
        guard !displayText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(displayText, forType: .string)
        copiedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            copiedFlash = false
        }
    }
}
