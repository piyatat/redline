#if os(iOS) && canImport(SwiftUI)
import SwiftUI
import RedlineShared

extension View {
    /// Tag a view as a designer region. In designer mode it shows an orange
    /// outline and opens the markup sheet on tap.
    public func redlineRegion(_ name: String, state: String? = nil) -> some View {
        modifier(DesignerRegionTagModifier(name: name, state: state))
    }

    /// Enables designer capture on this view tree (Debug). Calls `Redline.install` on appear.
    public func designerOverlay(
        screen: String = "app",
        spec: String? = nil,
        state: String? = nil,
        context: DesignerContext = EmptyDesignerContext(),
        feedbackBaseURL: URL? = nil,
        inspectPort: UInt16 = UInt16(RedlinePorts.simulatorInspectStart)
    ) -> some View {
        modifier(
            DesignerRootModifier(
                screen: screen,
                spec: spec,
                context: context,
                state: state,
                feedbackBaseURL: feedbackBaseURL,
                inspectPort: inspectPort
            )
        )
    }
}
private struct DesignerRegionTagModifier: ViewModifier {
    let name: String
    let state: String?
    @ObservedObject private var controller = DesignerModeController.shared

    func body(content: Content) -> some View {
        content
            .accessibilityIdentifier("redlineRegion:\(name)")
            .overlay {
                if controller.isDesignerModeActive && !controller.showMarkup && !controller.isSaving && !controller.isCapturing {
                    ZStack {
                        Rectangle()
                            .fill(Color.orange.opacity(0.12))
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.orange, lineWidth: 2)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        controller.beginMarkup(forRegion: name)
                    }
                }
            }
            .onAppear { RegionRegistry.shared.register(name) }
            .onDisappear { RegionRegistry.shared.unregister(name) }
    }
}
#endif
