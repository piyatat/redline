import Foundation
import RedlineShared

/// Thread-safe mirror of receiver settings for the Network.framework HTTP queue.
final class ReceiverSettingsSnapshot: @unchecked Sendable {
    private let lock = NSLock()
    private var apiToken: String?
    private var maxBodyBytes: Int = 8 * 1024 * 1024

    func update(from settings: AgentSettings) {
        lock.lock()
        defer { lock.unlock() }
        let trimmed = settings.apiToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        apiToken = (trimmed?.isEmpty == false) ? trimmed : nil
        maxBodyBytes = max(1, settings.maxFeedbackBodyBytes)
    }

    func token() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return apiToken
    }

    func bodyLimit() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return maxBodyBytes
    }
}
