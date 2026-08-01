#if os(iOS)
import Foundation

/// Tracks live `redlineRegion` tags so designer mode can fall back to whole-screen markup.
@MainActor
final class RegionRegistry: ObservableObject {
    static let shared = RegionRegistry()

    @Published private(set) var regionNames: Set<String> = []
    private var retainCounts: [String: Int] = [:]

    var regionCount: Int { regionNames.count }
    var hasAnnotatedRegions: Bool { !regionNames.isEmpty }

    func register(_ name: String) {
        retainCounts[name, default: 0] += 1
        regionNames.insert(name)
    }

    func unregister(_ name: String) {
        guard let count = retainCounts[name] else { return }
        if count <= 1 {
            retainCounts.removeValue(forKey: name)
            regionNames.remove(name)
        } else {
            retainCounts[name] = count - 1
        }
    }
}
#endif
