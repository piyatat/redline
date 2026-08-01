import AppKit
import SwiftUI

/// Expands SwiftUI content to fill an NSHostingView / split pane.
struct SplitPaneHost<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Side-by-side panes; leading width is saved to UserDefaults and restored on launch.
struct PersistentHSplitView<Leading: View, Trailing: View>: NSViewRepresentable {
    var autosaveName: String
    var leadingMinWidth: CGFloat = 240
    var trailingMinWidth: CGFloat = 320
    var defaultLeadingWidth: CGFloat = 320
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    func makeCoordinator() -> Coordinator {
        Coordinator(storageKey: autosaveName + ".leadingWidth", defaultPrimary: defaultLeadingWidth)
    }

    func makeNSView(context: Context) -> RestoringSplitView {
        let split = RestoringSplitView()
        split.isVertical = true
        split.dividerStyle = .paneSplitter
        split.delegate = context.coordinator
        context.coordinator.leadingMin = leadingMinWidth
        context.coordinator.trailingMin = trailingMinWidth
        split.restoration = context.coordinator

        let left = NSHostingView(rootView: SplitPaneHost(content: leading))
        let right = NSHostingView(rootView: SplitPaneHost(content: trailing))
        configureHostingFill(left)
        configureHostingFill(right)
        context.coordinator.leadingHost = left
        context.coordinator.trailingHost = right

        split.addArrangedSubview(left)
        split.addArrangedSubview(right)
        split.setHoldingPriority(.init(260), forSubviewAt: 0)
        split.setHoldingPriority(.defaultLow, forSubviewAt: 1)
        return split
    }

    func updateNSView(_ split: RestoringSplitView, context: Context) {
        context.coordinator.leadingMin = leadingMinWidth
        context.coordinator.trailingMin = trailingMinWidth
        context.coordinator.leadingHost?.rootView = SplitPaneHost(content: leading)
        context.coordinator.trailingHost?.rootView = SplitPaneHost(content: trailing)
    }

    final class Coordinator: NSObject, NSSplitViewDelegate, SplitRestoration {
        var leadingHost: NSHostingView<SplitPaneHost<Leading>>?
        var trailingHost: NSHostingView<SplitPaneHost<Trailing>>?
        var leadingMin: CGFloat = 240
        var trailingMin: CGFloat = 320

        let storageKey: String
        let defaultPrimary: CGFloat
        private(set) var didRestore = false
        private var suppressSave = false

        init(storageKey: String, defaultPrimary: CGFloat) {
            self.storageKey = storageKey
            self.defaultPrimary = defaultPrimary
        }

        func restore(into splitView: NSSplitView) {
            guard !didRestore, splitView.arrangedSubviews.count >= 2 else { return }
            let bounds = splitView.bounds.width
            guard bounds > 1 else { return }

            let saved = UserDefaults.standard.object(forKey: storageKey) as? Double
            var primary = CGFloat(saved ?? Double(defaultPrimary))
            primary = min(max(primary, leadingMin), max(leadingMin, bounds - trailingMin))

            suppressSave = true
            splitView.setPosition(primary, ofDividerAt: 0)
            suppressSave = false
            didRestore = true
        }

        func splitViewDidResizeSubviews(_ notification: Notification) {
            guard !suppressSave, didRestore,
                  let splitView = notification.object as? NSSplitView,
                  splitView.arrangedSubviews.count >= 2 else { return }
            let primary = splitView.arrangedSubviews[0].frame.width
            guard primary > 1 else { return }
            UserDefaults.standard.set(Double(primary), forKey: storageKey)
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainMinCoordinate proposedMinimumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            leadingMin
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainMaxCoordinate proposedMaximumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            splitView.bounds.width - trailingMin
        }
    }
}

/// Top / bottom panes; top height is saved to UserDefaults and restored on launch.
struct PersistentVSplitView<Top: View, Bottom: View>: NSViewRepresentable {
    var autosaveName: String
    var topMinHeight: CGFloat = 200
    var bottomMinHeight: CGFloat = 140
    var defaultTopHeight: CGFloat = 420
    @ViewBuilder var top: () -> Top
    @ViewBuilder var bottom: () -> Bottom

    func makeCoordinator() -> Coordinator {
        Coordinator(storageKey: autosaveName + ".topHeight", defaultPrimary: defaultTopHeight)
    }

    func makeNSView(context: Context) -> RestoringSplitView {
        let split = RestoringSplitView()
        split.isVertical = false
        split.dividerStyle = .paneSplitter
        split.delegate = context.coordinator
        context.coordinator.topMin = topMinHeight
        context.coordinator.bottomMin = bottomMinHeight
        split.restoration = context.coordinator

        let topHost = NSHostingView(rootView: SplitPaneHost(content: top))
        let bottomHost = NSHostingView(rootView: SplitPaneHost(content: bottom))
        configureHostingFill(topHost)
        configureHostingFill(bottomHost)
        context.coordinator.topHost = topHost
        context.coordinator.bottomHost = bottomHost

        split.addArrangedSubview(topHost)
        split.addArrangedSubview(bottomHost)
        split.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        split.setHoldingPriority(.init(260), forSubviewAt: 1)
        return split
    }

    func updateNSView(_ split: RestoringSplitView, context: Context) {
        context.coordinator.topMin = topMinHeight
        context.coordinator.bottomMin = bottomMinHeight
        context.coordinator.topHost?.rootView = SplitPaneHost(content: top)
        context.coordinator.bottomHost?.rootView = SplitPaneHost(content: bottom)
    }

    final class Coordinator: NSObject, NSSplitViewDelegate, SplitRestoration {
        var topHost: NSHostingView<SplitPaneHost<Top>>?
        var bottomHost: NSHostingView<SplitPaneHost<Bottom>>?
        var topMin: CGFloat = 200
        var bottomMin: CGFloat = 140

        let storageKey: String
        let defaultPrimary: CGFloat
        private(set) var didRestore = false
        private var suppressSave = false

        init(storageKey: String, defaultPrimary: CGFloat) {
            self.storageKey = storageKey
            self.defaultPrimary = defaultPrimary
        }

        func restore(into splitView: NSSplitView) {
            guard !didRestore, splitView.arrangedSubviews.count >= 2 else { return }
            let bounds = splitView.bounds.height
            guard bounds > 1 else { return }

            let saved = UserDefaults.standard.object(forKey: storageKey) as? Double
            var primary = CGFloat(saved ?? Double(defaultPrimary))
            primary = min(max(primary, topMin), max(topMin, bounds - bottomMin))

            suppressSave = true
            splitView.setPosition(primary, ofDividerAt: 0)
            suppressSave = false
            didRestore = true
        }

        func splitViewDidResizeSubviews(_ notification: Notification) {
            guard !suppressSave, didRestore,
                  let splitView = notification.object as? NSSplitView,
                  splitView.arrangedSubviews.count >= 2 else { return }
            let primary = splitView.arrangedSubviews[0].frame.height
            guard primary > 1 else { return }
            UserDefaults.standard.set(Double(primary), forKey: storageKey)
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainMinCoordinate proposedMinimumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            topMin
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainMaxCoordinate proposedMaximumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            splitView.bounds.height - bottomMin
        }
    }
}

// MARK: - Shared restore hook

protocol SplitRestoration: AnyObject {
    func restore(into splitView: NSSplitView)
}

final class RestoringSplitView: NSSplitView {
    weak var restoration: SplitRestoration?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleRestore()
    }

    override func layout() {
        super.layout()
        scheduleRestore()
    }

    private var restoreScheduled = false

    private func scheduleRestore() {
        guard window != nil, bounds.width > 1, bounds.height > 1, !restoreScheduled else { return }
        restoreScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.restoreScheduled = false
            self.restoration?.restore(into: self)
        }
    }
}

private func configureHostingFill(_ view: NSView) {
    view.setContentHuggingPriority(.defaultLow, for: .horizontal)
    view.setContentHuggingPriority(.defaultLow, for: .vertical)
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
}
