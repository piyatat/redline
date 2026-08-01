#if os(iOS)
import UIKit

enum SnapshotRenderer {
    static func captureKeyWindowPNGBase64() -> String {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) else {
            return ""
        }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { ctx in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        return image.pngData()?.base64EncodedString() ?? ""
    }
}
#endif
