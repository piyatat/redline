#if os(iOS)
import UIKit

/// Installs a window-level two-finger long-press to toggle designer mode.
/// Uses a gesture on the window itself (not a hit-stealing overlay) so normal
/// touches and region markup still work.
final class DesignerGestureInstaller: NSObject, UIGestureRecognizerDelegate {
    static let shared = DesignerGestureInstaller()

    private var installed = false
    private static let toggleGestureName = "dev.redline.designer.toggle"

    func installIfNeeded() {
        guard !installed else { return }
        installed = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowsChanged),
            name: UIWindow.didBecomeKeyNotification,
            object: nil
        )
        attachToAllWindows()
    }

    @objc private func windowsChanged() {
        attachToAllWindows()
    }

    private func attachToAllWindows() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            for window in scene.windows {
                attachGestures(to: window)
            }
        }
    }

    private func attachGestures(to window: UIWindow) {
        let alreadyAttached = window.gestureRecognizers?.contains {
            $0.name == Self.toggleGestureName
        } ?? false
        guard !alreadyAttached else { return }

        // Remove legacy blocking overlay from earlier builds if present.
        window.viewWithTag(90_421)?.removeFromSuperview()

        let recognizer = UILongPressGestureRecognizer(
            target: self,
            action: #selector(twoFingerLongPress(_:))
        )
        recognizer.name = Self.toggleGestureName
        recognizer.numberOfTouchesRequired = 2
        recognizer.minimumPressDuration = 0.45
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        window.addGestureRecognizer(recognizer)
    }

    @objc private func twoFingerLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        Task { @MainActor in
            DesignerModeController.shared.toggleDesignerMode()
        }
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
#endif
