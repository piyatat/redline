import Foundation
import RedlineShared

#if os(iOS)
import UIKit
#endif

public enum Redline {
    private static var isInstalled = false
    /// Optional host-provided key/values attached to every feedback `runtime` block.
    public static var runtimeUserInfo: [String: String] = [:]
    /// Optional free-form notes attached to every feedback `runtime` block.
    public static var runtimeNotes: String?

    public static func setRuntimeUserInfo(_ info: [String: String]) {
        runtimeUserInfo = info
    }

    public static func setRuntimeNotes(_ notes: String?) {
        runtimeNotes = notes
    }

    /// Install Redline in the host app. Debug-only — call behind `#if DEBUG`.
    public static func install(
        screen: String = "app",
        spec: String? = nil,
        state: String? = nil,
        context designerContext: DesignerContext = EmptyDesignerContext(),
        feedbackBaseURL: URL? = nil,
        inspectPort: UInt16 = UInt16(RedlinePorts.simulatorInspectStart)
    ) {
        #if os(iOS)
        guard _isDebugBuild else { return }
        let url = feedbackBaseURL ?? FeedbackTransport.defaultFeedbackURL()
        FeedbackTransport.shared.configure(baseURL: url)
        Task { @MainActor in
            DesignerModeController.shared.activate(
                screen: screen,
                spec: spec,
                context: designerContext,
                state: state
            )
        }
        InspectorTCPService.shared.start(port: inspectPort)
        isInstalled = true
        #else
        _ = screen
        _ = spec
        _ = state
        _ = designerContext
        _ = feedbackBaseURL
        _ = inspectPort
        #endif
    }

    /// Update screen / spec / state labels used on the next Save (e.g. when navigating).
    public static func updateScreen(screen: String, spec: String? = nil, state: String? = nil) {
        #if os(iOS)
        guard _isDebugBuild else { return }
        Task { @MainActor in
            DesignerModeController.shared.updateScreen(screen: screen, spec: spec, state: state)
        }
        #else
        _ = screen
        _ = spec
        _ = state
        #endif
    }

    public static var installed: Bool {
        #if os(iOS)
        return isInstalled
        #else
        return false
        #endif
    }

    #if os(iOS)
    private static var _isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    #endif
}

#if os(iOS)
extension Redline {
    /// Fire-and-forget POST (logs failures to stderr). Prefer `postFeedbackAwaiting` from Save.
    public static func postFeedback(_ payload: FeedbackPayload) {
        guard _isDebugBuild else { return }
        Task {
            do {
                try await postFeedbackAwaiting(payload)
            } catch {
                fputs("[Redline] feedback FAILED → \(FeedbackTransport.shared.debugBaseURL): \(error.localizedDescription)\n", stderr)
            }
        }
    }

    /// Awaitable POST — callers can keep markup open on failure.
    public static func postFeedbackAwaiting(_ payload: FeedbackPayload) async throws {
        guard _isDebugBuild else { return }
        try await FeedbackTransport.shared.post(payload)
        fputs("[Redline] feedback OK → \(FeedbackTransport.shared.debugBaseURL)\n", stderr)
    }
}
#endif
