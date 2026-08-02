import RedlineServer
import SwiftUI

@main
struct iOSDemoApp: App {
    init() {
        #if DEBUG
        Redline.install(
            screen: "demo-home",
            spec: "screens/demo-home.screen.md",
            context: DemoDesignerContext()
        )
        #endif
    }

    var body: some Scene {
        WindowGroup {
            DemoHomeView()
                .designerOverlay(
                    screen: "demo-home",
                    spec: "screens/demo-home.screen.md",
                    context: DemoDesignerContext()
                )
        }
    }
}

private struct DemoHomeView: View {
    @ObservedObject private var designer = DesignerModeController.shared

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Redline iOS Demo")
                        .font(.largeTitle.bold())
                    Text(designer.isDesignerModeActive
                         ? "Tap a region or Whole screen to markup."
                         : "Tap Enter designer, then pick a region or whole screen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .redlineRegion("Header")

                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(height: 120)
                    .overlay {
                        Text("Design feedback, live")
                    }
                    .padding(.horizontal)
                    .redlineRegion("Hero")

                Button("Leave design feedback") {}
                    .buttonStyle(.borderedProminent)
                    .redlineRegion("CTA")

                Spacer()

                Button {
                    designer.toggleDesignerMode()
                } label: {
                    Label(
                        designer.isDesignerModeActive ? "Exit designer" : "Enter designer",
                        systemImage: designer.isDesignerModeActive ? "xmark.circle" : "pencil.tip.crop.circle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(designer.isDesignerModeActive ? .orange : .accentColor)
                .padding(.horizontal)
                .padding(.bottom, 24)
                .disabled(designer.showMarkup)
            }
            .padding(.top, 72)
            .navigationTitle("Demo")
        }
        .navigationViewStyle(.stack)
    }
}
