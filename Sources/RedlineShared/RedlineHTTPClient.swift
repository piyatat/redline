import Foundation

public struct RedlineHTTPClient: Sendable {
    public var baseURL: URL
    public var apiToken: String?

    public init(baseURL: URL = URL(string: "http://127.0.0.1:\(RedlinePorts.feedbackDefault)")!, apiToken: String? = nil) {
        self.baseURL = baseURL
        if let apiToken {
            self.apiToken = apiToken
        } else {
            let env = ProcessInfo.processInfo.environment
            let raw = env[RedlineEnvironment.apiTokenKey]
            let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.apiToken = (trimmed?.isEmpty == false) ? trimmed : nil
        }
    }

    public func health() throws -> Bool {
        let (data, response) = try get(path: RedlinePaths.healthRoute)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
        return String(data: data, encoding: .utf8) == "ok"
    }

    public func inboxList() throws -> [InboxItem] {
        let (data, response) = try get(path: RedlinePaths.inboxRoute)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw RedlineHTTPError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([InboxItem].self, from: data)
    }

    /// Update inbox item status (MCP / CLI). `status` is `pending|agent_running|applied|failed`.
    @discardableResult
    public func inboxSetStatus(id: String, status: String, summary: String? = nil) throws -> InboxItem {
        struct Body: Encodable {
            var status: String
            var summary: String?
        }
        let payload = try JSONEncoder().encode(Body(status: status, summary: summary))
        let (data, response) = try post(
            path: RedlinePaths.inboxStatusRoute(id: id),
            body: payload,
            contentType: "application/json"
        )
        guard let http = response as? HTTPURLResponse else {
            throw RedlineHTTPError.badStatus(-1)
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw RedlineHTTPError.badStatus(http.statusCode, message: message)
        }
        // Re-fetch so callers get the updated item.
        let items = try inboxList()
        guard let item = items.first(where: { $0.id == id }) else {
            throw RedlineHTTPError.badStatus(404, message: "Item not found after status update")
        }
        return item
    }

    private func get(path: String) throws -> (Data, URLResponse) {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw RedlineHTTPError.invalidURL
        }
        var request = URLRequest(url: url)
        if let apiToken, !apiToken.isEmpty {
            request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        }
        return try URLSession.shared.synchronousData(for: request)
    }

    private func post(path: String, body: Data, contentType: String) throws -> (Data, URLResponse) {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw RedlineHTTPError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if let apiToken, !apiToken.isEmpty {
            request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        }
        return try URLSession.shared.synchronousData(for: request)
    }
}

public enum RedlineHTTPError: Error, LocalizedError {
    case invalidURL
    case badStatus(Int, message: String? = nil)
    case timeout(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid Redline URL"
        case .badStatus(let code, let message):
            if let message, !message.isEmpty { return "HTTP \(code): \(message)" }
            return "HTTP \(code)"
        case .timeout(let message): return message
        }
    }
}

private extension URLSession {
    func synchronousData(for request: URLRequest) throws -> (Data, URLResponse) {
        var result: Result<(Data, URLResponse), Error>?
        let semaphore = DispatchSemaphore(value: 0)
        let task = dataTask(with: request) { data, response, error in
            if let error {
                result = .failure(error)
            } else if let data, let response {
                result = .success((data, response))
            } else {
                result = .failure(RedlineHTTPError.badStatus(-1))
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        return try result!.get()
    }
}
