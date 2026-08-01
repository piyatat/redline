import AppKit
import Foundation
import RedlineShared
import UserNotifications

@MainActor
final class AgentRunner: ObservableObject {
    @Published var lastMessage: String = ""
    /// Live / last agent stdout+stderr for the log pane.
    @Published var agentLog: String = ""
    @Published var isBusy: Bool = false
    @Published var activeInboxItemId: String?
    /// True when the next pane message can `--continue` the last CLI session.
    @Published var canContinueSession: Bool = false
    /// Seconds since the current agent run started (0 when idle).
    @Published var runElapsedSeconds: Int = 0

    private var runningJobIDs: Set<String> = []
    private var pendingJobs: [AgentJob] = []
    private var recentDedupeKeys: [String: Date] = [:]
    private var lastSessionProjectPath: String?
    private var runStartedAt: Date?
    private var lastOutputAt: Date?
    private var lastHeartbeatAt: Date?
    private var heartbeatTimer: Timer?
    private var processController: AgentProcessController?
    private let maxQueue = 10
    private let dedupeWindow: TimeInterval = 5
    private let agentTimeout: TimeInterval = 600

    func clearLog() {
        agentLog = ""
        lastMessage = ""
    }

    /// Reflect MCP/HTTP status updates in the log pane (no local process).
    func noteExternalStatus(id: String, status: String, summary: String?) {
        let clip = (summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let line: String
        if clip.isEmpty {
            line = "MCP status → \(status) (\(id.prefix(8))…)\n"
        } else {
            line = "MCP status → \(status): \(clip.prefix(200))\n"
        }
        appendLog(line)
        lastMessage = "MCP: \(status)"
    }

    /// Stop the currently running agent process and clear any queued jobs.
    func stop(inbox: InboxStore? = nil) {
        let queued = pendingJobs
        pendingJobs.removeAll()
        if let inbox {
            for job in queued {
                // Never demote an MCP (or other) claim that already moved off pending.
                guard let live = inbox.item(id: job.inboxItemId), live.status == .pending else { continue }
                inbox.updateStatus(
                    id: job.inboxItemId,
                    status: .pending,
                    proposalSummary: "Cancelled — queue cleared"
                )
            }
        }
        guard isBusy || processController != nil else {
            if !queued.isEmpty {
                lastMessage = "Queue cleared"
                appendLog("Queue cleared (\(queued.count) job(s))\n")
            }
            return
        }
        appendLog("\n⏹ Stop requested…\n")
        lastMessage = "Stopping…"
        processController?.cancel()
    }

    func resetSession() {
        canContinueSession = false
        lastSessionProjectPath = nil
        appendLog("── New session ──\n")
    }

    func loadLog(for item: InboxItem) {
        guard !isBusy else { return }
        guard let path = item.bundleDirectory else {
            agentLog = ""
            return
        }
        let logURL = URL(fileURLWithPath: path).appendingPathComponent("agent-hook.log")
        if let data = try? Data(contentsOf: logURL),
           let text = String(data: data, encoding: .utf8),
           !text.isEmpty {
            agentLog = text
        } else if let summary = item.proposalSummary, !summary.isEmpty {
            agentLog = summary
        } else {
            agentLog = ""
        }
    }

    /// Interactive follow-up from the agent log pane.
    func sendChat(
        message: String,
        settings: AgentSettings,
        inbox: InboxStore,
        item: InboxItem?
    ) async {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch settings.agentBackend {
        case .shellHook:
            appendLog("Interactive chat needs Cursor Agent CLI or Claude Code CLI (Settings tab).\n")
            lastMessage = "Shell hook cannot chat"
            return
        case .cursorCLI, .claudeCLI:
            break
        }

        guard ensureConsent(settings: settings, inbox: inbox, itemId: item?.id) else { return }

        let project = settings.projectPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !project.isEmpty, FileManager.default.fileExists(atPath: project) else {
            appendLog("Set Settings → Project folder before chatting.\n")
            lastMessage = "Project folder missing"
            return
        }

        guard !isBusy else {
            appendLog("Agent busy — wait for the current run to finish.\n")
            return
        }

        // Don't steal an MCP/CLI claim with local chat.
        if settings.onNewFeedback == .awaitDesktopMCP {
            appendLog("Desktop MCP mode — use `/redline-wait` in Cursor instead of local chat.\n")
            lastMessage = "Chat disabled in MCP mode"
            return
        }
        if let item, item.status == .agentRunning, activeInboxItemId != item.id {
            appendLog("Item is already Running (MCP or another job) — finish or mark Pending first.\n")
            lastMessage = "Item already running"
            return
        }

        let continueSession = canContinueSession && lastSessionProjectPath == project
        let statusBeforeChat = item?.status ?? .pending
        let runId = UUID().uuidString
        runningJobIDs.insert(runId)
        isBusy = true
        activeInboxItemId = item?.id
        beginRunActivity()
        defer {
            endRunActivity()
            runningJobIDs.remove(runId)
            isBusy = !runningJobIDs.isEmpty
            if runningJobIDs.isEmpty {
                activeInboxItemId = nil
            }
        }

        if let item {
            inbox.updateStatus(id: item.id, status: .agentRunning, proposalSummary: "Chat…")
        }

        appendLog("\n> \(trimmed)\n")
        if continueSession {
            appendLog("(continuing session)\n")
        }
        lastMessage = "Sending…"

        let bundlePath = item?.bundleDirectory
        let result: (success: Bool, message: String, output: String, cancelled: Bool)
        switch settings.agentBackend {
        case .cursorCLI:
            result = await runCursorCLI(
                settings: settings,
                prompt: trimmed,
                continueSession: continueSession,
                bundleDirectory: bundlePath
            )
        case .claudeCLI:
            result = await runClaudeCLI(
                settings: settings,
                prompt: trimmed,
                continueSession: continueSession,
                bundleDirectory: bundlePath
            )
        case .shellHook:
            return
        }

        appendLog("\n── \(result.message) ──\n")

        if result.success {
            markSessionContinuable(projectPath: project)
        }

        if let item {
            if let path = item.bundleDirectory {
                let logURL = URL(fileURLWithPath: path).appendingPathComponent("agent-hook.log")
                try? agentLog.data(using: .utf8)?.write(to: logURL)
            }
            let clipped = String((agentLog.isEmpty ? result.output : agentLog).prefix(2000))
            if result.cancelled {
                inbox.updateStatus(id: item.id, status: .pending, proposalSummary: "Stopped by user\n\(clipped)")
            } else if result.success {
                // Restore pre-chat status as-is (including agent_running for MCP claims).
                inbox.updateStatus(id: item.id, status: statusBeforeChat, proposalSummary: "Chat ok\n\(clipped)")
            } else {
                inbox.updateStatus(id: item.id, status: .failed, proposalSummary: "\(result.message)\n\(clipped)")
            }
        }

        lastMessage = result.message
        if !result.success && !result.cancelled {
            notify(title: "Redline agent failed", body: result.message)
        } else if result.cancelled {
            notify(title: "Redline agent", body: "Stopped")
        }
    }

    func handleNewFeedback(
        item: InboxItem,
        settings: AgentSettings,
        inbox: InboxStore
    ) async {
        if isDuplicate(payload: item.payload) {
            // Terminal so MCP wait won't reclaim; never demote an existing claim.
            updateStatusIfUnclaimed(
                inbox: inbox,
                id: item.id,
                status: .applied,
                proposalSummary: "Duplicate of recent feedback — ignored (safe to Remove)"
            )
            lastMessage = "Ignored duplicate feedback"
            appendLog("Ignored duplicate feedback (\(item.payload.screen) · \(item.payload.region))\n")
            notify(title: "Redline", body: "Duplicate feedback ignored")
            return
        }

        switch settings.onNewFeedback {
        case .off:
            updateStatusIfUnclaimed(
                inbox: inbox,
                id: item.id,
                status: .pending,
                proposalSummary: "Received — use Send to AI"
            )
            lastMessage = "Feedback received (auto-trigger off)"
            return
        case .notify:
            notify(
                title: "Redline feedback",
                body: "\(item.payload.screen) · \(item.payload.region)"
            )
            updateStatusIfUnclaimed(
                inbox: inbox,
                id: item.id,
                status: .pending,
                proposalSummary: "Bundle written — notify only"
            )
            lastMessage = "Feedback received (notify only)"
            return
        case .awaitDesktopMCP:
            notify(
                title: "Redline feedback",
                body: "\(item.payload.screen) · \(item.payload.region) — awaiting Cursor MCP"
            )
            if let staged = FeedbackBundleStager.stageIfPossible(
                projectPath: settings.projectPath,
                bundleDirectory: item.bundleDirectory
            ) {
                appendLog("Staged feedback for MCP → \(staged.path)\n")
            } else if settings.projectPath?.isEmpty == false {
                appendLog("Could not stage .redline-feedback — set Project folder and ensure bundle exists\n")
            }
            updateStatusIfUnclaimed(
                inbox: inbox,
                id: item.id,
                status: .pending,
                proposalSummary: "Awaiting Cursor desktop — run /redline-wait (MCP). CLI auto-trigger is off."
            )
            lastMessage = "Feedback received — awaiting Cursor MCP (/redline-wait)"
            appendLog("Desktop MCP mode — not starting Agent CLI for \(item.payload.screen)\n")
            return
        case .triggerAgent:
            notify(
                title: "Redline feedback",
                body: "\(item.payload.screen) · \(item.payload.region)"
            )
            guard ensureConsent(settings: settings, inbox: inbox, itemId: item.id) else { return }
            guard let path = item.bundleDirectory else {
                inbox.updateStatus(
                    id: item.id,
                    status: .failed,
                    proposalSummary: "Bundle missing — cannot run agent"
                )
                return
            }
            await enqueue(
                job: AgentJob(inboxItemId: item.id, bundleDirectory: URL(fileURLWithPath: path)),
                settings: settings,
                inbox: inbox,
                item: item
            )
        }
    }

    func runManually(item: InboxItem, settings: AgentSettings, inbox: InboxStore) async {
        guard ensureConsent(settings: settings, inbox: inbox, itemId: item.id) else { return }
        guard let path = item.bundleDirectory else {
            lastMessage = "No bundle directory — cannot run agent"
            appendLog("No bundle directory — cannot run agent\n")
            return
        }
        await enqueue(
            job: AgentJob(inboxItemId: item.id, bundleDirectory: URL(fileURLWithPath: path)),
            settings: settings,
            inbox: inbox,
            item: item
        )
    }

    @discardableResult
    private func ensureConsent(settings: AgentSettings, inbox: InboxStore, itemId: String?) -> Bool {
        guard settings.consentExternalAi else {
            let note = "Enable “Allow Redline to call external AI” in Settings before running an agent"
            if let itemId, let live = inbox.item(id: itemId), live.status != .agentRunning {
                inbox.updateStatus(id: itemId, status: .pending, proposalSummary: note)
            }
            lastMessage = note
            appendLog("\(note)\n")
            return false
        }
        return true
    }

    private func isDuplicate(payload: FeedbackPayload) -> Bool {
        let commentKey = payload.comment.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = "\(payload.capturedTs)|\(payload.region)|\(commentKey)"
        let now = Date()
        recentDedupeKeys = recentDedupeKeys.filter { now.timeIntervalSince($0.value) < dedupeWindow }
        if recentDedupeKeys[key] != nil { return true }
        recentDedupeKeys[key] = now
        return false
    }

    /// Avoid clobbering MCP/CLI claim (`agent_running`) or finished outcomes.
    private func updateStatusIfUnclaimed(
        inbox: InboxStore,
        id: String,
        status: InboxItem.Status,
        proposalSummary: String
    ) {
        guard let live = inbox.item(id: id) else { return }
        switch live.status {
        case .agentRunning, .applied, .failed:
            appendLog("Skipped status update — item already \(live.status.rawValue)\n")
            return
        case .pending:
            inbox.updateStatus(id: id, status: status, proposalSummary: proposalSummary)
        }
    }

    private func enqueue(
        job: AgentJob,
        settings: AgentSettings,
        inbox: InboxStore,
        item: InboxItem
    ) async {
        let liveStatus = inbox.item(id: item.id)?.status ?? item.status
        if liveStatus == .agentRunning || activeInboxItemId == item.id {
            lastMessage = "Agent already running for this item"
            appendLog("Skipped enqueue — already running for \(item.payload.screen)\n")
            return
        }
        if pendingJobs.contains(where: { $0.inboxItemId == item.id }) {
            lastMessage = "Already queued"
            appendLog("Skipped enqueue — already queued for \(item.payload.screen)\n")
            return
        }
        if runningJobIDs.count >= 1 {
            guard pendingJobs.count < maxQueue else {
                lastMessage = "Agent queue full"
                appendLog("Agent queue full\n")
                inbox.updateStatus(
                    id: item.id,
                    status: .pending,
                    proposalSummary: "Queue full — retry Send to AI"
                )
                notify(title: "Redline agent", body: "Queue full — retry Send to AI")
                return
            }
            pendingJobs.append(job)
            let position = pendingJobs.count
            inbox.updateStatus(
                id: item.id,
                status: .pending,
                proposalSummary: "Queued (#\(position))"
            )
            lastMessage = "Queued behind running agent job"
            appendLog("Queued job for \(item.payload.screen)\n")
            return
        }
        await run(job: job, settings: settings, inbox: inbox, item: item)
        while let next = pendingJobs.first {
            pendingJobs.removeFirst()
            guard let item = inbox.item(id: next.inboxItemId) else { continue }
            switch item.status {
            case .agentRunning, .applied, .failed:
                appendLog("Skipped queued job — item already \(item.status.rawValue)\n")
                continue
            case .pending:
                break
            }
            await run(job: next, settings: settings, inbox: inbox, item: item)
        }
    }

    private func run(
        job: AgentJob,
        settings: AgentSettings,
        inbox: InboxStore,
        item: InboxItem
    ) async {
        // Re-check in case MCP claimed while we were queued.
        if let live = inbox.item(id: job.inboxItemId) {
            let claimedElsewhere = live.status == .agentRunning && activeInboxItemId != job.inboxItemId
            if claimedElsewhere || live.status == .applied || live.status == .failed {
                appendLog("Skipped run — item already \(live.status.rawValue)\n")
                lastMessage = "Skipped — item already \(live.status.displayName)"
                return
            }
        }
        runningJobIDs.insert(job.id)
        isBusy = true
        activeInboxItemId = job.inboxItemId
        let label = settings.agentBackend.displayName
        // Fresh feedback run starts a new session (do not --continue).
        canContinueSession = false
        lastSessionProjectPath = nil
        agentLog = ""
        appendLog("── \(label) · \(item.payload.screen) · \(item.payload.region) ──\n")
        appendLog("Started \(Date().formatted(date: .abbreviated, time: .standard))\n")
        appendLog("Streaming live progress below…\n\n")
        beginRunActivity()
        inbox.updateStatus(id: job.inboxItemId, status: .agentRunning, proposalSummary: "Running \(label)…")
        lastMessage = "Running \(label)…"
        defer {
            endRunActivity()
            runningJobIDs.remove(job.id)
            isBusy = !runningJobIDs.isEmpty
            if runningJobIDs.isEmpty {
                activeInboxItemId = nil
            }
        }

        let agentResult: (success: Bool, message: String, output: String, cancelled: Bool)
        switch settings.agentBackend {
        case .cursorCLI:
            agentResult = await runCursorCLI(
                settings: settings,
                prompt: loadPrompt(job: job, item: item),
                continueSession: false,
                bundleDirectory: job.bundleDirectory.path
            )
        case .claudeCLI:
            agentResult = await runClaudeCLI(
                settings: settings,
                prompt: loadPrompt(job: job, item: item),
                continueSession: false,
                bundleDirectory: job.bundleDirectory.path
            )
        case .shellHook:
            let hook = await runShellHook(settings: settings, job: job)
            agentResult = (hook.success, hook.message, hook.output, hook.cancelled)
        }

        let display = agentLog.isEmpty ? agentResult.output : agentLog
        let clipped = String(display.prefix(2000))
        let logURL = job.bundleDirectory.appendingPathComponent("agent-hook.log")
        try? display.data(using: .utf8)?.write(to: logURL)

        appendLog("\n── \(agentResult.message) ──\n")

        if agentResult.cancelled {
            let summary = "Stopped by user\n\(clipped)"
            inbox.updateStatus(id: job.inboxItemId, status: .pending, proposalSummary: summary)
            lastMessage = "Stopped"
            notify(title: "Redline agent", body: "Stopped")
            return
        }

        if agentResult.success, settings.agentBackend != .shellHook {
            markSessionContinuable(projectPath: settings.projectPath ?? "")
        }

        if !agentResult.success {
            let summary = "\(agentResult.message)\n\(clipped)"
            inbox.updateStatus(id: job.inboxItemId, status: .failed, proposalSummary: summary)
            lastMessage = agentResult.message
            notify(title: "Redline agent failed", body: agentResult.message)
            return
        }

        // Shell hook only opens/notifies — keep pending. CLI agents mark Finished.
        let doneStatus: InboxItem.Status = settings.agentBackend == .shellHook ? .pending : .applied
        let summary = "\(label) completed\n\(clipped)"
        inbox.updateStatus(id: job.inboxItemId, status: doneStatus, proposalSummary: summary)
        lastMessage = "\(label) completed"
        notify(title: "Redline agent", body: "\(label) completed")
    }

    private func markSessionContinuable(projectPath: String) {
        let project = projectPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !project.isEmpty else { return }
        lastSessionProjectPath = project
        canContinueSession = true
    }

    private func beginRunActivity() {
        runStartedAt = Date()
        lastOutputAt = Date()
        lastHeartbeatAt = Date()
        runElapsedSeconds = 0
        heartbeatTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickHeartbeat()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    private func endRunActivity() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        runStartedAt = nil
        lastOutputAt = nil
        lastHeartbeatAt = nil
        runElapsedSeconds = 0
    }

    private func tickHeartbeat() {
        guard isBusy, let start = runStartedAt else { return }
        let elapsed = Int(Date().timeIntervalSince(start))
        runElapsedSeconds = elapsed
        lastMessage = "Running… \(elapsed)s"

        // If the CLI is quiet, show we're still alive so the UI doesn't look frozen.
        let lastOut = lastOutputAt ?? start
        let quiet = Date().timeIntervalSince(lastOut)
        let sinceBeat = Date().timeIntervalSince(lastHeartbeatAt ?? start)
        if quiet >= 4, sinceBeat >= 4 {
            appendLog("… still working (\(elapsed)s, waiting for agent output)\n")
            lastHeartbeatAt = Date()
        }
    }

    private func noteAgentOutput() {
        lastOutputAt = Date()
        lastHeartbeatAt = Date()
    }

    private func appendLog(_ chunk: String) {
        agentLog += chunk
        let lines = chunk.split(separator: "\n", omittingEmptySubsequences: false)
        if let last = lines.last(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            let text = String(last)
            // Don't let heartbeat lines wipe more useful status from the toolbar forever.
            if !text.hasPrefix("… still working") {
                lastMessage = text
            }
        }
    }

    private func makeOutputHandler(parseStreamJSON: Bool) -> @Sendable (String) -> Void {
        let parser = parseStreamJSON ? AgentStreamProgressParser() : nil
        return { [weak self] chunk in
            Task { @MainActor in
                guard let self else { return }
                self.noteAgentOutput()
                if let parser {
                    for fragment in parser.ingest(chunk) {
                        self.appendLog(fragment)
                    }
                } else {
                    self.appendLog(chunk)
                }
            }
        }
    }

    private func loadPrompt(job: AgentJob, item: InboxItem) -> String {
        let promptURL = job.bundleDirectory.appendingPathComponent("prompt.md")
        if let data = try? Data(contentsOf: promptURL), let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }
        return AgentPromptBuilder().makePrompt(for: item.payload, bundleDirectory: job.bundleDirectory)
    }

    private func runCursorCLI(
        settings: AgentSettings,
        prompt: String,
        continueSession: Bool,
        bundleDirectory: String?
    ) async -> (success: Bool, message: String, output: String, cancelled: Bool) {
        let controller = AgentProcessController()
        processController = controller
        defer { processController = nil }

        var effectivePrompt = prompt
        if let bundleDirectory,
           let staged = stageBundleInProject(projectPath: settings.projectPath ?? "", bundlePath: bundleDirectory) {
            effectivePrompt = """
            Feedback bundle staged at \(staged.path) (composite.png, feedback.json, prompt.md). Read those files.

            \(prompt)
            """
            appendLog("Staged feedback bundle → \(staged.path)\n")
        }

        let parser = AgentStreamProgressParser()
        let onOutput: @Sendable (String) -> Void = { [weak self] chunk in
            Task { @MainActor in
                guard let self else { return }
                self.noteAgentOutput()
                for fragment in parser.ingest(chunk) {
                    self.appendLog(fragment)
                }
            }
        }
        let result = await CursorCLIAgent.run(
            .init(
                projectPath: settings.projectPath ?? "",
                prompt: effectivePrompt,
                cursorAgentPath: settings.cursorAgentPath,
                timeout: agentTimeout,
                continueSession: continueSession,
                controller: controller,
                onOutput: onOutput
            )
        )
        for fragment in parser.finish() {
            appendLog(fragment)
        }
        return (result.success, result.message, result.output, result.cancelled)
    }

    /// Copy key bundle files into `<project>/.redline-feedback` so Cursor (cwd = project) can read them.
    private func stageBundleInProject(projectPath: String, bundlePath: String) -> URL? {
        do {
            let dest = try FeedbackBundleStager.stage(projectPath: projectPath, bundleDirectory: bundlePath)
            return dest
        } catch {
            appendLog("Could not stage bundle for Cursor: \(error.localizedDescription)\n")
            return nil
        }
    }

    private func runClaudeCLI(
        settings: AgentSettings,
        prompt: String,
        continueSession: Bool,
        bundleDirectory: String?
    ) async -> (success: Bool, message: String, output: String, cancelled: Bool) {
        let controller = AgentProcessController()
        processController = controller
        defer { processController = nil }

        let parser = AgentStreamProgressParser()
        let onOutput: @Sendable (String) -> Void = { [weak self] chunk in
            Task { @MainActor in
                guard let self else { return }
                self.noteAgentOutput()
                for fragment in parser.ingest(chunk) {
                    self.appendLog(fragment)
                }
            }
        }
        let result = await ClaudeCLIAgent.run(
            .init(
                projectPath: settings.projectPath ?? "",
                prompt: prompt,
                bundleDirectory: bundleDirectory,
                claudeAgentPath: settings.claudeAgentPath,
                timeout: agentTimeout,
                continueSession: continueSession,
                controller: controller,
                onOutput: onOutput
            )
        )
        for fragment in parser.finish() {
            appendLog(fragment)
        }
        return (result.success, result.message, result.output, result.cancelled)
    }

    private func runShellHook(
        settings: AgentSettings,
        job: AgentJob
    ) async -> (success: Bool, message: String, output: String, cancelled: Bool) {
        let hookPath = (settings.hookPath?.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 }
        guard let hookPath else {
            appendLog("No agent hook configured\n")
            return (false, "No agent hook configured", "", false)
        }
        return await runHookProcess(path: hookPath, job: job)
    }

    private func runHookProcess(path: String, job: AgentJob) async -> (success: Bool, message: String, output: String, cancelled: Bool) {
        let controller = AgentProcessController()
        processController = controller
        defer { processController = nil }

        let onOutput = makeOutputHandler(parseStreamJSON: false)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let streamed = ProcessStreamer.run(
                    executable: URL(fileURLWithPath: path),
                    arguments: [job.inboxItemId, job.bundleDirectory.path],
                    currentDirectory: nil,
                    environment: ProcessStreamer.enrichedPATH(from: ProcessInfo.processInfo.environment),
                    timeout: self.agentTimeout,
                    controller: controller,
                    onOutput: onOutput
                )
                let message = streamed.cancelled
                    ? "stopped by user"
                    : (streamed.success ? "exit 0" : "exit \(streamed.exitCode)")
                continuation.resume(returning: (streamed.success, message, streamed.output, streamed.cancelled))
            }
        }
    }

    private func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request, withCompletionHandler: nil)
        NSApplication.shared.requestUserAttention(.informationalRequest)
    }
}
