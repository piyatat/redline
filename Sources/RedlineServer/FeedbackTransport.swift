import Foundation
import RedlineShared

public final class FeedbackTransport: @unchecked Sendable {
    public static let shared = FeedbackTransport()

    private let session: URLSession
    private var baseURL: URL
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
        self.baseURL = baseURL
    }

    /// For debug logging only.
    public var debugBaseURL: String { baseURL.absoluteString }

    public func post(_ payload: FeedbackPayload) async throws {
        try payload.validateSchema()
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = Self.apiTokenFromEnvironment(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try payload.encode()

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw FeedbackTransportError.badStatus(code)
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

    public var errorDescription: String? {
        switch self {
        case .badStatus(let code):
            return "Feedback POST failed with HTTP \(code)"
        }
    }
}
