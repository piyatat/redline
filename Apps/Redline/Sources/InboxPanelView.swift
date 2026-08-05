import AppKit
import SwiftUI
import RedlineShared

struct InboxPanelView: View {
    @ObservedObject var inbox: InboxStore
    @ObservedObject var settingsStore: AgentSettingsStore
    @ObservedObject var agentRunner: AgentRunner

    @State private var selectedId: String?
    @State private var editingItem: InboxItem?
    @State private var pendingDelete: InboxItem?
    @State private var confirmClearFinished = false
    @State private var searchText = ""
    @State private var statusFilter: InboxStatusFilter = .all

    private var filteredItems: [InboxItem] {
        inbox.items.filter { item in
            statusFilter.matches(item.status) && matchesSearch(item)
        }
    }

    private var selectedItem: InboxItem? {
        if let selectedId, let match = filteredItems.first(where: { $0.id == selectedId }) {
            return match
        }
        if let selectedId, let match = inbox.item(id: selectedId), statusFilter.matches(match.status), matchesSearch(match) {
            return match
        }
        return filteredItems.first
    }

    var body: some View {
        PersistentVSplitView(
            autosaveName: "Redline.Inbox.Vertical",
            topMinHeight: 240,
            bottomMinHeight: 140
        ) {
            PersistentHSplitView(
                autosaveName: "Redline.Inbox.Horizontal",
                leadingMinWidth: 260,
                trailingMinWidth: 380
            ) {
                listPane
            } trailing: {
                detailPane
            }
        } bottom: {
            AgentLogPaneView(
                agentRunner: agentRunner,
                settingsStore: settingsStore,
                inbox: inbox,
                selectedItem: selectedItem
            )
        }
        .onAppear {
            syncSelection()
            if let item = selectedItem {
                agentRunner.loadLog(for: item)
            }
        }
        .onChange(of: inbox.items.count) { _ in
            syncSelection()
        }
        .onChange(of: searchText) { _ in
            syncSelection()
        }
        .onChange(of: statusFilter) { _ in
            syncSelection()
        }
        .onChange(of: selectedId) { _ in
            if let item = selectedItem {
                agentRunner.loadLog(for: item)
            }
        }
        .sheet(item: $editingItem) { item in
            FeedbackEditSheet(
                item: item,
                onCancel: { editingItem = nil },
                onSave: { screen, region, comment, state, spec in
                    let id = item.id
                    if inbox.updateFeedback(
                        id: id,
                        screen: screen,
                        region: region,
                        comment: comment,
                        state: state,
                        spec: spec
                    ) {
                        editingItem = nil
                        selectedId = id
                        if let updated = inbox.item(id: id) {
                            agentRunner.loadLog(for: updated)
                        }
                    }
                }
            )
        }
        .confirmationDialog(
            "Remove feedback?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { item in
            Button("Remove", role: .destructive) {
                let target = item
                removeItem(target)
            }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text("“\(item.payload.screen) — \(item.payload.region)” will be removed from the Inbox and its bundle deleted from disk.")
        }
        .confirmationDialog(
            "Remove finished feedback?",
            isPresented: $confirmClearFinished,
            titleVisibility: .visible
        ) {
            Button("Remove \(inbox.finishedCount) finished", role: .destructive) {
                clearFinished()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes finished items from the Inbox and removes their bundles from disk. Pending, running, and failed items are kept.")
        }
    }

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Inbox")
                    .appFont(.headline)
                Spacer()
                Text(countLabel)
                    .appFont(.caption, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(Capsule())

                if inbox.finishedCount > 0 {
                    Button {
                        confirmClearFinished = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove finished (applied) feedback")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search screen, comment…", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Picker("Status", selection: $statusFilter) {
                    ForEach(InboxStatusFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            Divider()

            if inbox.items.isEmpty {
                emptyState(
                    title: "No feedback yet",
                    subtitle: "Send feedback from iOS or Android to land it here."
                )
            } else if filteredItems.isEmpty {
                emptyState(
                    title: "No matches",
                    subtitle: "Try another search or status filter."
                )
            } else {
                List(selection: $selectedId) {
                    ForEach(filteredItems) { item in
                        InboxRowView(item: item)
                            .tag(item.id)
                            .contextMenu {
                                Button("Edit…") { editingItem = item }
                                    .disabled(item.status == .agentRunning)
                                Menu("Set status") {
                                    ForEach(InboxItem.Status.manuallyAssignable, id: \.self) { status in
                                        Button {
                                            _ = inbox.setStatusManually(id: item.id, status: status)
                                        } label: {
                                            if item.status == status {
                                                Label(status.displayName, systemImage: "checkmark")
                                            } else {
                                                Text(status.displayName)
                                            }
                                        }
                                    }
                                }
                                Divider()
                                Button("Remove…", role: .destructive) { pendingDelete = item }
                                    .disabled(item.status == .agentRunning)
                            }
                    }
                    .onDelete { offsets in
                        let toRemove = offsets.compactMap { filteredItems[safe: $0] }
                        if let first = toRemove.first {
                            pendingDelete = first
                        }
                    }
                }
                .listStyle(.sidebar)
            }

            if let error = inbox.lastError {
                Text(error)
                    .appFont(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var countLabel: String {
        if filteredItems.count == inbox.items.count {
            return "\(inbox.items.count)"
        }
        return "\(filteredItems.count)/\(inbox.items.count)"
    }

    private func emptyState(title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .appFont(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .appFont(.headline)
            Text(subtitle)
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func matchesSearch(_ item: InboxItem) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let haystack = [
            item.payload.screen,
            item.payload.region,
            item.payload.comment,
            item.payload.state ?? "",
            item.payload.spec ?? "",
            item.payload.platform,
            item.proposalSummary ?? "",
            item.status.rawValue,
        ].joined(separator: "\n")
        return haystack.localizedCaseInsensitiveContains(query)
    }

    private func syncSelection() {
        if let selectedId, filteredItems.contains(where: { $0.id == selectedId }) {
            return
        }
        selectedId = filteredItems.first?.id
    }

    private func clearFinished() {
        let removedIds = Set(inbox.items.filter { InboxStore.isFinished($0.status) }.map(\.id))
        _ = inbox.removeFinished(deleteBundles: true)
        if let selectedId, removedIds.contains(selectedId) {
            self.selectedId = filteredItems.first?.id
        }
        syncSelection()
    }

    @ViewBuilder
    private var detailPane: some View {
        if let item = selectedItem {
            InboxDetailView(
                item: item,
                preferDesktopMCP: settingsStore.settings.onNewFeedback == .awaitDesktopMCP,
                canStopLocalAgent: agentRunner.isBusy,
                onSendToAI: {
                    Task {
                        await agentRunner.runManually(
                            item: item,
                            settings: settingsStore.settings,
                            inbox: inbox
                        )
                    }
                },
                onStop: {
                    agentRunner.stop(inbox: inbox)
                },
                onEdit: {
                    editingItem = item
                },
                onDelete: {
                    pendingDelete = item
                },
                onOpenBundle: {
                    openBundle(item)
                },
                onRevealPrompt: {
                    revealFile(named: "prompt.md", in: item)
                },
                onSetStatus: { status in
                    _ = inbox.setStatusManually(id: item.id, status: status)
                }
            )
        } else {
            VStack(spacing: 8) {
                Image(systemName: "text.bubble")
                    .appFont(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Select feedback")
                    .appFont(.headline)
                Text("Choose an inbox item to preview markup and run the agent.")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func removeItem(_ item: InboxItem) {
        let id = item.id
        pendingDelete = nil
        if inbox.remove(id: id) {
            if selectedId == id {
                selectedId = filteredItems.first?.id
            }
            syncSelection()
            if agentRunner.activeInboxItemId == id {
                agentRunner.clearLog()
            }
        }
    }

    private func openBundle(_ item: InboxItem) {
        guard let path = item.bundleDirectory else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func revealFile(named name: String, in item: InboxItem) {
        guard let path = item.bundleDirectory else { return }
        let url = URL(fileURLWithPath: path).appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            openBundle(item)
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

private enum InboxStatusFilter: String, CaseIterable, Identifiable {
    case all
    case open
    case finished
    case pending
    case running
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All statuses"
        case .open: return "Open (not finished)"
        case .finished: return "Finished"
        case .pending: return "Pending"
        case .running: return "Running"
        case .failed: return "Failed"
        }
    }

    func matches(_ status: InboxItem.Status) -> Bool {
        switch self {
        case .all: return true
        case .open: return InboxStore.isOpenWork(status)
        case .finished: return status == .applied
        case .pending: return status == .pending
        case .running: return status == .agentRunning
        case .failed: return status == .failed
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct InboxRowView: View {
    let item: InboxItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(item.payload.screen) · \(item.payload.region)")
                    .appFont(.body, weight: .medium)
                    .lineLimit(1)
                Spacer()
                StatusBadge(status: item.status)
            }
            Text(item.payload.comment.isEmpty ? "(no comment)" : item.payload.comment)
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(item.receivedAt.formatted(date: .abbreviated, time: .shortened))
                .appFont(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

private struct InboxDetailView: View {
    let item: InboxItem
    var preferDesktopMCP: Bool = false
    var canStopLocalAgent: Bool = false
    var onSendToAI: () -> Void
    var onStop: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onOpenBundle: () -> Void
    var onRevealPrompt: () -> Void
    var onSetStatus: (InboxItem.Status) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if preferDesktopMCP {
                    Text("Desktop MCP mode — run `/redline-wait` in Cursor to process this feedback.")
                        .appFont(.caption)
                        .foregroundStyle(.orange)
                }
                actions
                compositePreview
                commentSection
                runtimeSection
                pinsSection
                summarySection
                bundleSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(item.payload.screen) — \(item.payload.region)")
                    .appFont(.title2, weight: .semibold)
                statusPicker
                Spacer()
            }
            HStack(spacing: 12) {
                Label(
                    item.payload.platform,
                    systemImage: item.payload.platform.lowercased() == "android" ? "smartphone" : "iphone"
                )
                if let state = item.payload.state {
                    Text(state)
                }
                if let mode = item.payload.mode {
                    Text(mode)
                }
                Text(item.payload.capturedTs)
                    .foregroundStyle(.secondary)
            }
            .appFont(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var statusPicker: some View {
        Menu {
            ForEach(InboxItem.Status.manuallyAssignable, id: \.self) { status in
                Button {
                    onSetStatus(status)
                } label: {
                    if item.status == status {
                        Label(status.displayName, systemImage: "checkmark")
                    } else {
                        Text(status.displayName)
                    }
                }
            }
        } label: {
            StatusBadge(status: item.status)
        }
        .menuStyle(.borderlessButton)
        .help("Change status")
    }

    private var actions: some View {
        HStack(spacing: 8) {
            // Stop only when a local CLI process is running (MCP "Running" has no process to kill).
            if canStopLocalAgent {
                Button("Stop", role: .destructive, action: onStop)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            } else if !preferDesktopMCP, item.status != .agentRunning {
                Button("Send to AI", action: onSendToAI)
                    .buttonStyle(.borderedProminent)
                    .help("Run the configured AI backend")
            } else if item.status == .agentRunning, !canStopLocalAgent {
                Text("Running via MCP — use status menu to mark Finished/Pending when done.")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Edit", action: onEdit)
                .disabled(item.status == .agentRunning)

            Button("Open bundle", action: onOpenBundle)
                .disabled(item.bundleDirectory == nil)

            Button("prompt.md", action: onRevealPrompt)
                .disabled(item.bundleDirectory == nil)

            Spacer()

            Button("Remove", role: .destructive, action: onDelete)
                .disabled(item.status == .agentRunning)
        }
    }

    @ViewBuilder
    private var compositePreview: some View {
        if let data = Data(base64Encoded: item.payload.compositePngBase64),
           let nsImage = NSImage(data: data) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Marked-up screenshot")
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
                Text("Device capture with markup baked in (composite.png for agents).")
                    .appFont(.caption2)
                    .foregroundStyle(.tertiary)
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.08))
                    )
            }
        } else if !item.payload.compositePngBase64.isEmpty {
            Text("Marked-up screenshot unavailable — open the bundle to inspect composite.png.")
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Comment")
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Edit") { onEdit() }
                    .appFont(.caption)
                    .buttonStyle(.borderless)
                    .disabled(item.status == .agentRunning)
            }
            Text(item.payload.comment.isEmpty ? "—" : item.payload.comment)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var runtimeSection: some View {
        if let runtime = item.payload.runtime {
            VStack(alignment: .leading, spacing: 6) {
                Text("App / runtime")
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)

                runtimeLine("App", [runtime.appName, runtime.bundleId].compactMap { $0 }.joined(separator: " · "))
                if let version = runtime.appVersion {
                    let build = runtime.buildNumber.map { " (\($0))" } ?? ""
                    runtimeLine("Version", "\(version)\(build)")
                }
                runtimeLine(
                    "Device",
                    [runtime.deviceModel, runtime.systemName, runtime.systemVersion]
                        .compactMap { $0 }
                        .joined(separator: " ")
                )
                if let sim = runtime.isSimulator {
                    let label = item.payload.platform.lowercased() == "android" ? "Emulator" : "Simulator"
                    runtimeLine(label, sim ? "yes" : "no")
                }
                runtimeLine("Screen", runtime.screenBounds)
                if let top = runtime.topViewController {
                    runtimeLine("Top VC", top)
                }

                if let stack = runtime.viewControllerStack, !stack.isEmpty {
                    Text("VC stack")
                        .appFont(.caption2)
                        .foregroundStyle(.tertiary)
                    ForEach(Array(stack.prefix(8).enumerated()), id: \.offset) { _, name in
                        Text(name)
                            .appFont(.caption, design: .monospaced)
                            .textSelection(.enabled)
                    }
                    if stack.count > 8 {
                        Text("+\(stack.count - 8) more…")
                            .appFont(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if let callStack = runtime.callStack, !callStack.isEmpty {
                    Text("Call stack (first \(min(6, callStack.count)))")
                        .appFont(.caption2)
                        .foregroundStyle(.tertiary)
                    ForEach(Array(callStack.prefix(6).enumerated()), id: \.offset) { _, frame in
                        Text(frame)
                            .appFont(.caption2, design: .monospaced)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                }

                if let info = runtime.userInfo, !info.isEmpty {
                    Text("Host userInfo")
                        .appFont(.caption2)
                        .foregroundStyle(.tertiary)
                    ForEach(info.keys.sorted(), id: \.self) { key in
                        Text("\(key): \(info[key] ?? "")")
                            .appFont(.caption, design: .monospaced)
                            .textSelection(.enabled)
                    }
                }

                if let notes = runtime.notes, !notes.isEmpty {
                    Text(notes)
                        .appFont(.caption)
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private func runtimeLine(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(label)
                    .appFont(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 72, alignment: .leading)
                Text(value)
                    .appFont(.caption)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var pinsSection: some View {
        if !item.payload.pins.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pins")
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
                ForEach(Array(item.payload.pins.enumerated()), id: \.offset) { _, pin in
                    Text("\(pin.component): \(pin.pin)")
                        .appFont(.body, design: .monospaced)
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        if let summary = item.proposalSummary, !summary.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Agent note")
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
                Text(summary)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .textSelection(.enabled)
                Text("Full agent output is in the log pane below.")
                    .appFont(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var bundleSection: some View {
        if let path = item.bundleDirectory {
            VStack(alignment: .leading, spacing: 6) {
                Text("Bundle")
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
                Text(path)
                    .appFont(.caption, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct FeedbackEditSheet: View {
    let item: InboxItem
    var onCancel: () -> Void
    var onSave: (_ screen: String, _ region: String, _ comment: String, _ state: String?, _ spec: String?) -> Void

    @State private var screen: String
    @State private var region: String
    @State private var comment: String
    @State private var state: String
    @State private var spec: String

    init(
        item: InboxItem,
        onCancel: @escaping () -> Void,
        onSave: @escaping (_ screen: String, _ region: String, _ comment: String, _ state: String?, _ spec: String?) -> Void
    ) {
        self.item = item
        self.onCancel = onCancel
        self.onSave = onSave
        _screen = State(initialValue: item.payload.screen)
        _region = State(initialValue: item.payload.region)
        _comment = State(initialValue: item.payload.comment)
        _state = State(initialValue: item.payload.state ?? "")
        _spec = State(initialValue: item.payload.spec ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Edit feedback")
                    .appFont(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(screen, region, comment, state, spec)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(screen.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()

            Divider()

            Form {
                TextField("Screen", text: $screen)
                TextField("Region", text: $region)
                TextField("State (optional)", text: $state)
                TextField("Spec path (optional)", text: $spec)
                Section("Comment") {
                    TextEditor(text: $comment)
                        .appFont(.body)
                        .frame(minHeight: 120)
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .frame(minWidth: 480, minHeight: 420)
    }
}

private struct StatusBadge: View {
    let status: InboxItem.Status

    var body: some View {
        Text(label)
            .appFont(.caption2, weight: .semibold)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(foreground)
            .background(foreground.opacity(0.15))
            .clipShape(Capsule())
    }

    private var label: String {
        status.displayName
    }

    private var foreground: Color {
        switch status {
        case .pending: return .secondary
        case .agentRunning: return .blue
        case .applied: return .green
        case .failed: return .red
        }
    }
}
