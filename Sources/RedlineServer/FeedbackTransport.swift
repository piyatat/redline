import Foundation
import RedlineShared

public final class FeedbackTransport: @unchecked Sendable {
    public static let shared = FeedbackTransport()

    private let session: URLSession
    private let lock = NSLock()
    private var baseURL: URL
    private var configuredApiToken: String?
    private let encoder: JSONEncoder

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
        baseURL = Self.defaultFeedbackURL()
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
    }

    public static func defaultFeedbackURL() -> URL {
        if let raw = ProcessInfo.processInfo.environment[RedlineEnvironment.feedbackURLKey],
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "http://127.0.0.1:\(RedlinePorts.feedbackDefault)\(RedlinePaths.feedbackRoute)")!
    }

    public func configure(baseURL: URL) {
        lock.lock()
        self.baseURL = baseURL
        lock.unlock()
    }

    public func configureApiToken(_ token: String?) {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        configuredApiToken = (trimmed?.isEmpty == false) ? trimmed : nil
        lock.unlock()
    }

    /// For debug logging only.
    public var debugBaseURL: String {
        lock.lock()
        defer { lock.unlock() }
        return baseURL.absoluteString
    }

    public func post(_ payload: FeedbackPayload) async throws {
        try payload.validateSchema()
        let (url, token): (URL, String?) = {
            lock.lock()
            defer { lock.unlock() }
            return (baseURL, configuredApiToken ?? Self.apiTokenFromEnvironment())
        }()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try payload.encode()

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw FeedbackTransportError.badStatus(code)
            }
        } catch let error as FeedbackTransportError {
            throw error
        } catch let urlError as URLError {
            throw FeedbackTransportError.connectFailed(url.absoluteString, urlError)
        } catch {
            throw FeedbackTransportError.connectFailed(url.absoluteString, error)
        }
    }

    private static func apiTokenFromEnvironment() -> String? {
        let env = ProcessInfo.processInfo.environment
        let raw = env[RedlineEnvironment.apiTokenKey]
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }
}

public enum FeedbackTransportError: Error, LocalizedError {
    case badStatus(Int)
    case connectFailed(String, Error)

    public var errorDescription: String? {
        switch self {
        case .badStatus(let code):
            if code == 401 {
                return "Feedback POST failed with HTTP 401 — set REDLINE_API_TOKEN (or designerOverlay apiToken) to match Redline.app Settings."
            }
            return "Feedback POST failed with HTTP \(code)"
        case .connectFailed(let url, _):
            return "Failed to connect to \(url). Is Redline.app running on the Mac (127.0.0.1:8765)?"
        }
    }
}
