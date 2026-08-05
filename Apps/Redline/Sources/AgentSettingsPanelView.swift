import AppKit
import SwiftUI
import RedlineShared

struct AgentSettingsPanelView: View {
    @ObservedObject var settingsStore: AgentSettingsStore

    /// Bumped to re-run CLI discovery after Check again / path changes.
    @State private var cliCheckToken = 0
    @State private var copiedInstallFlash = false
    @State private var cursorDesktopFlash = false
    @State private var cursorDesktopMessage = ""
    @State private var showAdvanced = false
    @State private var showOptionalSendToAI = false

    /// Bound directly — no local mirror, no remounting sections on change.
    private var mode: AgentTriggerMode { settingsStore.settings.onNewFeedback }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                modePickerCard
                activeModeSetupCard
                advancedCard
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .appFont(.body)
        .onChange(of: settingsStore.settings.agentBackend) { _ in
            cliCheckToken += 1
            copiedInstallFlash = false
        }
        .onChange(of: mode) { _ in
            showOptionalSendToAI = false
            cliCheckToken += 1
        }
    }

    // MARK: - Mode picker

    private var modePickerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("When feedback arrives")
                .appFont(.headline)

            Picker("Mode", selection: modeBinding) {
                ForEach(AgentTriggerMode.settingsOrder, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 420, alignment: .leading)

            Text(mode.summary)
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var modeBinding: Binding<AgentTriggerMode> {
        Binding(
            get: { settingsStore.settings.onNewFeedback },
            set: { newValue in
                settingsStore.update { $0.onNewFeedback = newValue }
            }
        )
    }

    // MARK: - Active mode setup (one card — keeps VStack spacing even)

    @ViewBuilder
    private var activeModeSetupCard: some View {
        switch mode {
        case .awaitDesktopMCP:
            modeSetupCard(title: "Cursor desktop setup") {
                cursorDesktopSetupContent
            }
        case .triggerAgent:
            modeSetupCard(title: "Agent CLI setup") {
                autoAgentSetupContent
            }
        case .notify:
            modeSetupCard(title: "Notify-only setup") {
                notifySetupContent
            }
        case .off:
            modeSetupCard(title: "Manual Send to AI") {
                manualSetupContent
            }
        }
    }

    private func modeSetupCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .appFont(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Mode-specific setup

    @ViewBuilder
    private var cursorDesktopSetupContent: some View {
        labeledHelp(
            "Use this with Cursor’s desktop Agent so desktop MCP plugins stay available. Redline only stores + notifies; you drive the loop with `/redline-wait`."
        )

        projectFolderRow

        LabeledContent("Redline package") {
            HStack {
                TextField("SPM checkout with Package.swift", text: optionalBinding(\.redlinePackagePath))
                Button("Choose…") { pickDirectory(for: \.redlinePackagePath) }
                Button("Detect") {
                    if let path = CursorDesktopIntegration.resolvePackagePath(
                        explicit: settingsStore.settings.redlinePackagePath
                    ) {
                        settingsStore.update { $0.redlinePackagePath = path }
                    }
                }
            }
        }

        if let resolved = resolvedPackagePath {
            Text(resolved)
                .appFont(.caption, design: .monospaced)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        } else {
            Text("Point this at the Redline repo so Cursor can run `redline mcp`. Prefer `swift build --product redline` first.")
                .appFont(.caption)
                .foregroundStyle(.orange)
        }

        HStack {
            Button("Install into project…") {
                installCursorDesktop(openDeeplink: false)
            }
            .disabled(resolvedPackagePath == nil || projectPathMissing)

            Button("Open MCP install in Cursor") {
                installCursorDesktop(openDeeplink: true)
            }
            .disabled(resolvedPackagePath == nil)

            if cursorDesktopFlash {
                Text(cursorDesktopMessage)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }

        Text("Install writes `.cursor/mcp.json` (no API token), skill `redline-wait`, slash command `/redline-wait`, and gitignore entries into the project folder.")
            .appFont(.caption)
            .foregroundStyle(.secondary)

        DisclosureGroup("Optional: preconfigure Agent CLI", isExpanded: $showOptionalSendToAI) {
            labeledHelp(
                "Inbox hides Send to AI while MCP mode is selected. Configure CLI paths here only if you plan to switch to Agent CLI later — prefer `/redline-wait` in this mode."
            )
            consentToggle
            backendPickerAndDetails(includeProjectFolder: false)
        }
    }

    @ViewBuilder
    private var autoAgentSetupContent: some View {
        labeledHelp(
            "Each Send starts the CLI below. Do not also run `/redline-wait` on the same feedback — pick one path."
        )
        consentToggle
        backendPickerAndDetails(includeProjectFolder: true)
    }

    @ViewBuilder
    private var notifySetupContent: some View {
        labeledHelp(
            "Feedback is written to disk and you get a notification. No agent starts until you choose Send to AI on an inbox item."
        )
        DisclosureGroup("Configure Send to AI", isExpanded: $showOptionalSendToAI) {
            consentToggle
            backendPickerAndDetails(includeProjectFolder: true)
        }
    }

    @ViewBuilder
    private var manualSetupContent: some View {
        labeledHelp(
            "Inbox stays quiet. Open an item and press Send to AI when you want a run."
        )
        consentToggle
        backendPickerAndDetails(includeProjectFolder: true)
    }

    // MARK: - Shared AI backend bits

    private var consentToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Allow Redline to call external AI", isOn: consentBinding)
            Text("Required before Send to AI or auto CLI. Screenshots and comments are sent to the selected tool.")
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var consentBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.consentExternalAi },
            set: { newValue in settingsStore.update { $0.consentExternalAi = newValue } }
        )
    }

    @ViewBuilder
    private func backendPickerAndDetails(includeProjectFolder: Bool) -> some View {
        Picker("Backend", selection: backendBinding) {
            ForEach(AgentBackend.allCases, id: \.self) { backend in
                Text(backend.displayName).tag(backend)
            }
        }

        Text(settingsStore.settings.agentBackend.summary)
            .appFont(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        if includeProjectFolder, usesProjectFolder {
            projectFolderRow
        }

        if settingsStore.settings.agentBackend == .cursorCLI {
            LabeledContent("Cursor agent path") {
                HStack {
                    TextField("Optional override", text: optionalBinding(\.cursorAgentPath))
                    Button("Choose…") { pickFile(for: \.cursorAgentPath) }
                }
            }
            cliStatusCard(for: .cursorCLI)
        } else if settingsStore.settings.agentBackend == .claudeCLI {
            LabeledContent("Claude agent path") {
                HStack {
                    TextField("Optional override", text: optionalBinding(\.claudeAgentPath))
                    Button("Choose…") { pickFile(for: \.claudeAgentPath) }
                }
            }
            cliStatusCard(for: .claudeCLI)
        } else {
            LabeledContent("Agent hook") {
                HStack {
                    TextField(settingsStore.defaultHookPath, text: hookBinding)
                    Button("Choose…") { pickFile(for: \.hookPath) }
                }
            }
            Button("Reset hook to default") {
                settingsStore.resetHookToDefault()
            }
        }
    }

    private var backendBinding: Binding<AgentBackend> {
        Binding(
            get: { settingsStore.settings.agentBackend },
            set: { newValue in settingsStore.update { $0.agentBackend = newValue } }
        )
    }

    private var projectFolderRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("Project folder") {
                HStack {
                    TextField("Repo the agent should edit", text: optionalBinding(\.projectPath))
                    Button("Choose…") { pickDirectory(for: \.projectPath) }
                }
            }
            Text("The app repo Cursor / Claude should modify. Feedback assets stage under `.redline-feedback/`.")
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Advanced

    private var advancedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup(isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 16) {
                    receiverBlock
                    Divider()
                    appearanceBlock
                }
                .padding(.top, 8)
            } label: {
                Text("Advanced — receiver & appearance")
                    .appFont(.body, weight: .semibold)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var receiverBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Receiver")
                .appFont(.headline)
            Text("HTTP endpoint where host apps (iOS / Android) post feedback. Binds loopback only (`127.0.0.1`). iOS Simulator reaches this directly. Android emulator uses `10.0.2.2` (host alias). Physical devices need a reverse tunnel (`adb reverse` on Android — see docs/device-setup.md and docs/android-setup.md). Set a token if other local processes share this Mac.")
                .appFont(.caption)
                .foregroundStyle(.secondary)

            SecureField("API token", text: optionalBinding(\.apiToken))
            Text("Required for Agent CLI auto-run. Optional for notify / MCP-await / manual Send. Same value as `REDLINE_API_TOKEN` on the device. Not written into project `mcp.json`.")
                .appFont(.caption)
                .foregroundStyle(.secondary)

            if settingsStore.settings.apiToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                Text("No token set — any local process can POST to the receiver. Agent CLI auto-run is blocked until you set one.")
                    .appFont(.caption)
                    .foregroundStyle(.orange)
            }

            LabeledContent("Max body bytes") {
                TextField(
                    "",
                    value: maxBodyBinding,
                    format: .number
                )
                .frame(width: 120)
            }

            LabeledContent("Feedback URL") {
                Text("http://127.0.0.1:\(RedlinePorts.feedbackDefault)\(RedlinePaths.feedbackRoute)")
                    .textSelection(.enabled)
                    .appFont(.body, design: .monospaced)
            }
        }
    }

    private var maxBodyBinding: Binding<Int> {
        Binding(
            get: { settingsStore.settings.maxFeedbackBodyBytes },
            set: { newValue in settingsStore.update { $0.maxFeedbackBodyBytes = newValue } }
        )
    }

    private var appearanceBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Appearance")
                .appFont(.headline)
            Text("Scales text across Inbox, Settings, and the log pane.")
                .appFont(.caption)
                .foregroundStyle(.secondary)

            LabeledContent("App font size") {
                HStack(spacing: 8) {
                    Slider(
                        value: fontSizeBinding,
                        in: AgentSettings.logFontSizeRange,
                        step: 1
                    )
                    Text("\(Int(settingsStore.settings.logFontSize)) pt")
                        .appFont(.body, design: .monospaced)
                        .frame(width: 44, alignment: .trailing)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Inbox · Settings · Status")
                    .appFont(.headline)
                Text("The quick brown fox — designer feedback preview")
                    .appFont(.body)
                Text("agent -p --force  ·  monospaced log sample")
                    .appFont(.body, design: .monospaced)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { settingsStore.settings.logFontSize },
            set: { newValue in settingsStore.update { $0.logFontSize = newValue } }
        )
    }

    private func labeledHelp(_ text: String) -> some View {
        Text(text)
            .appFont(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 2)
    }

    // MARK: - CLI status

    @ViewBuilder
    private func cliStatusCard(for backend: AgentBackend) -> some View {
        let _ = cliCheckToken
        let status = cliStatus(for: backend)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: status.isInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(status.isInstalled ? Color.green : Color.orange)
                    .appFont(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(status.isInstalled ? "CLI installed" : "CLI not found")
                        .appFont(.body, weight: .semibold)
                    if let path = status.pathLabel {
                        Text(path)
                            .appFont(.caption, design: .monospaced)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else {
                        Text("Redline can’t find the \(backend.displayName) binary on this Mac.")
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                Button("Check again") {
                    cliCheckToken += 1
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if !status.isInstalled {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Install")
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .center, spacing: 8) {
                        Text(status.installCommand)
                            .appFont(.caption, design: .monospaced)
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                        Button {
                            copyInstallCommand(status.installCommand)
                        } label: {
                            Text(copiedInstallFlash ? "Copied" : "Copy")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Text(status.authHint)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)

                    if let docs = status.docsURL {
                        Link("Open install docs", destination: docs)
                            .appFont(.caption)
                    }
                }
                .padding(.top, 2)
            } else {
                Text(status.authHint)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (status.isInstalled ? Color.green : Color.orange).opacity(0.08)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke((status.isInstalled ? Color.green : Color.orange).opacity(0.25))
        )
    }

    private struct CLIStatus {
        var isInstalled: Bool
        var pathLabel: String?
        var installCommand: String
        var authHint: String
        var docsURL: URL?
    }

    private func cliStatus(for backend: AgentBackend) -> CLIStatus {
        switch backend {
        case .cursorCLI:
            let s = CursorCLIAgent.installStatus(override: settingsStore.settings.cursorAgentPath)
            return CLIStatus(
                isInstalled: s.isInstalled,
                pathLabel: s.pathLabel,
                installCommand: s.installCommand,
                authHint: s.authHint,
                docsURL: s.docsURL
            )
        case .claudeCLI:
            let s = ClaudeCLIAgent.installStatus(override: settingsStore.settings.claudeAgentPath)
            return CLIStatus(
                isInstalled: s.isInstalled,
                pathLabel: s.pathLabel,
                installCommand: s.installCommand,
                authHint: s.authHint,
                docsURL: s.docsURL
            )
        case .shellHook:
            return CLIStatus(
                isInstalled: true,
                pathLabel: nil,
                installCommand: "",
                authHint: "",
                docsURL: nil
            )
        }
    }

    private func copyInstallCommand(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copiedInstallFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            copiedInstallFlash = false
        }
    }

    private var usesProjectFolder: Bool {
        switch settingsStore.settings.agentBackend {
        case .cursorCLI, .claudeCLI: return true
        case .shellHook: return false
        }
    }

    private var resolvedPackagePath: String? {
        CursorDesktopIntegration.resolvePackagePath(explicit: settingsStore.settings.redlinePackagePath)
    }

    private var projectPathMissing: Bool {
        let path = settingsStore.settings.projectPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty || !FileManager.default.fileExists(atPath: path)
    }

    private func installCursorDesktop(openDeeplink: Bool) {
        guard let package = resolvedPackagePath else {
            flashCursorDesktop("Set Redline package path first")
            return
        }
        settingsStore.update { $0.redlinePackagePath = package }

        do {
            let config = CursorDesktopIntegration.makeServerConfig(
                packagePath: package,
                workspaceRoot: settingsStore.settings.projectPath,
                apiToken: nil,
                includeAPITokenInEnv: false
            )
            let deeplink = try CursorDesktopIntegration.installDeeplink(for: config)

            if let project = settingsStore.settings.projectPath?.trimmingCharacters(in: .whitespacesAndNewlines),
               !project.isEmpty {
                let result = try CursorDesktopIntegration.installIntoProject(
                    projectPath: project,
                    packagePath: package,
                    workspaceRoot: project
                )
                let binaryHint: String
                if result.deeplink.contains(".build/") {
                    binaryHint = ""
                } else {
                    binaryHint = " (no built binary — ran swift run fallback; prefer `swift build --product redline`)"
                }
                flashCursorDesktop("Wrote MCP + skill + /redline-wait → \(result.mcpJSONPath)\(binaryHint)")
            } else if !openDeeplink {
                flashCursorDesktop("Set Project folder to write mcp.json / skill")
                return
            }

            if openDeeplink {
                NSWorkspace.shared.open(deeplink)
                flashCursorDesktop("Opened Cursor MCP install — confirm in Cursor")
            }
            settingsStore.save()
        } catch {
            flashCursorDesktop(error.localizedDescription)
        }
    }

    private func flashCursorDesktop(_ message: String) {
        cursorDesktopMessage = message
        cursorDesktopFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            cursorDesktopFlash = false
        }
    }

    private var hookBinding: Binding<String> {
        Binding(
            get: { settingsStore.settings.hookPath ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                settingsStore.update { $0.hookPath = trimmed.isEmpty ? nil : trimmed }
            }
        )
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<AgentSettings, String?>) -> Binding<String> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                settingsStore.update { $0[keyPath: keyPath] = trimmed.isEmpty ? nil : trimmed }
            }
        )
    }

    private func pickDirectory(for keyPath: WritableKeyPath<AgentSettings, String?>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settingsStore.update { $0[keyPath: keyPath] = url.path }
            settingsStore.save()
            cliCheckToken += 1
        }
    }

    private func pickFile(for keyPath: WritableKeyPath<AgentSettings, String?>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settingsStore.update { $0[keyPath: keyPath] = url.path }
            settingsStore.save()
            cliCheckToken += 1
        }
    }
}
