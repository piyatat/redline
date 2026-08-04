#if os(iOS)
import SwiftUI
import UIKit
import RedlineShared

@MainActor
public final class DesignerModeController: ObservableObject {
    public static let shared = DesignerModeController()

    @Published public private(set) var isDesignerModeActive = false
    @Published public var activeRegion: String?
    @Published public var showMarkup = false
    @Published public var markupComment = ""
    @Published public var strokes: [MarkupStroke] = []
    @Published public var toolsUsed: Set<String> = []

    @Published public var isSaving = false
    /// True only while the window is snapshotted — hides Saving overlay / region chrome from the PNG.
    @Published public var isCapturing = false
    @Published public var saveError: String?

    public private(set) var screenName: String = "screen"
    public private(set) var specPath: String?
    private var context: DesignerContext = EmptyDesignerContext()
    private var stateName: String?

    private init() {}

    public func activate(screen: String, spec: String?, context: DesignerContext, state: String? = nil) {
        screenName = screen
        specPath = spec
        self.context = context
        stateName = state
        DesignerGestureInstaller.shared.installIfNeeded()
    }

    public func updateScreen(screen: String, spec: String? = nil, state: String? = nil) {
        screenName = screen
        if let spec { specPath = spec }
        if let state { stateName = state }
    }

    /// Canonical region id used when marking up the entire screen.
    public static let screenRegionName = "Screen"

    public func toggleDesignerMode() {
        guard !isSaving else { return }
        if isDesignerModeActive {
            isDesignerModeActive = false
            showMarkup = false
            activeRegion = nil
            return
        }

        isDesignerModeActive = true
        // No annotated components → jump straight into whole-screen markup.
        if RegionRegistry.shared.regionCount == 0 {
            beginMarkup(forRegion: Self.screenRegionName)
        }
    }

    public func beginScreenMarkup() {
        beginMarkup(forRegion: Self.screenRegionName)
    }

    public func beginMarkup(forRegion region: String) {
        guard !isSaving else { return }
        activeRegion = region
        pendingBridge = nil
        strokes = []
        toolsUsed = []
        markupComment = ""
        saveError = nil
        showMarkup = true
        isDesignerModeActive = true
    }

    public func beginMarkup(fromBridge bridge: StartRedlineBridge) {
        guard !isSaving else { return }
        activeRegion = bridge.region
        pendingBridge = bridge
        strokes = []
        toolsUsed = []
        markupComment = ""
        saveError = nil
        showMarkup = true
        isDesignerModeActive = true
    }

    public func cancelMarkup() {
        guard !isSaving else { return }
        showMarkup = false
        activeRegion = nil
        pendingBridge = nil
        markupComment = ""
        strokes = []
        toolsUsed = []
        saveError = nil
    }

    private var pendingBridge: StartRedlineBridge?

    public func pins(for region: String) -> [DesignerPin] {
        context.pins(screen: screenName, region: region)
    }

    public func saveMarkup() async {
        guard let region = activeRegion else { return }
        guard !isSaving else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        let bridgePins = pendingBridge?.pins ?? []
        let contextPins = pins(for: region)
        let mergedPins = bridgePins.isEmpty ? contextPins : bridgePins
        let inspectorBlock = pendingBridge.map { RedlineBridge.inspectorPayload(from: $0) }
        let trimmedComment = markupComment.trimmingCharacters(in: .whitespacesAndNewlines)
        let strokeSnapshot = strokes
        let toolsSnapshot = Array(toolsUsed)

        // Hide markup chrome for a clean UI shot, then bake strokes into the PNG for Mac/agent.
        // isCapturing suppresses Saving overlay + region outlines for the snapshot window.
        showMarkup = false
        isCapturing = true
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        let snapshot = SnapshotRenderer.captureKeyWindowPNGBase64(strokes: strokeSnapshot)
        isCapturing = false
        // Allow Saving overlay to appear for the POST phase.
        await Task.yield()
        guard !snapshot.isEmpty else {
            showMarkup = true
            saveError = "Could not capture screenshot"
            fputs("[Redline] saveMarkup failed: empty screenshot\n", stderr)
            return
        }

        let payload = FeedbackPayload(
            screen: screenName,
            region: region,
            state: stateName,
            platform: "ios",
            mode: UITraitCollection.current.userInterfaceStyle == .dark ? "dark" : "light",
            spec: specPath,
            capturedTs: ISO8601DateFormatter().string(from: Date()),
            comment: trimmedComment.isEmpty ? "(no comment)" : trimmedComment,
            pins: mergedPins,
            toolsUsed: toolsSnapshot,
            strokes: strokeSnapshot,
            compositePngBase64: snapshot,
            inspector: inspectorBlock,
            runtime: AppRuntimeContextCapture.capture(
                userInfo: Redline.runtimeUserInfo,
                notes: Redline.runtimeNotes
            )
        )
        do {
            try await Redline.postFeedbackAwaiting(payload)
            pendingBridge = nil
            activeRegion = nil
            markupComment = ""
            strokes = []
            toolsUsed = []
            saveError = nil
        } catch {
            // Keep markup sheet open so the designer can retry after fixing the receiver.
            fputs("[Redline] saveMarkup failed: \(error.localizedDescription)\n", stderr)
            saveError = error.localizedDescription
            showMarkup = true
        }
    }
}
#endif
