import Foundation
import Network
import RedlineShared

final class FeedbackHTTPServer: @unchecked Sendable {
    /// Throws when the bundle could not be stored — caller maps to HTTP 5xx so devices keep markup.
    typealias FeedbackHandler = @Sendable (FeedbackPayload) async throws -> Void
    /// Returns JSON body + HTTP status for a status update request.
    typealias InboxStatusHandler = @Sendable (_ id: String, _ status: String, _ summary: String?) async -> (statusCode: Int, body: String)

    private var listener: NWListener?
    private let port: UInt16
    private let handler: FeedbackHandler
    private let inboxProvider: @Sendable () -> Data?
    private let inboxStatusHandler: InboxStatusHandler?
    private let authToken: @Sendable () -> String?
    private let maxBodyBytes: @Sendable () -> Int
    private let queue = DispatchQueue(label: "dev.redline.feedback-http")

    init(
        port: UInt16 = UInt16(RedlinePorts.feedbackDefault),
        authToken: @escaping @Sendable () -> String? = { nil },
        maxBodyBytes: @escaping @Sendable () -> Int = { 8 * 1024 * 1024 },
        inboxProvider: @escaping @Sendable () -> Data? = { nil },
        inboxStatusHandler: InboxStatusHandler? = nil,
        handler: @escaping FeedbackHandler
    ) {
        self.port = port
        self.handler = handler
        self.inboxProvider = inboxProvider
        self.inboxStatusHandler = inboxStatusHandler
        self.authToken = authToken
        self.maxBodyBytes = maxBodyBytes
    }

    func start() throws {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        // Prefer dual-stack so Simulator IPv4 127.0.0.1 can connect.
        if let ipOptions = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ipOptions.version = .any
        }

        let nwPort = NWEndpoint.Port(rawValue: port)!
        // Loopback only — physical devices need a USB reverse tunnel to 127.0.0.1 (stock iproxy is Mac→device).
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: nwPort)
        let listener = try NWListener(using: parameters)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }

        let boundPort = port
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                fputs("Redline receiver listening on http://127.0.0.1:\(boundPort) (loopback only)\n", stderr)
            case .failed(let error):
                fputs("Redline receiver failed: \(error)\n", stderr)
            default:
                break
            }
        }

        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        receiveAll(connection: connection, buffer: Data())
    }

    private func receiveAll(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            if let error {
                fputs("Redline receiver read error: \(error)\n", stderr)
                connection.cancel()
                return
            }

            var next = buffer
            if let data, !data.isEmpty {
                next.append(data)
            }

            switch self.tryParseHTTP(next, isComplete: isComplete) {
            case .needMore:
                if isComplete {
                    if next.isEmpty {
                        connection.cancel()
                    } else {
                        self.respond(connection: connection, status: 400, body: "Incomplete request", contentType: "text/plain")
                    }
                    return
                }
                if next.count > self.maxBodyBytes() + 64 * 1024 {
                    self.respond(connection: connection, status: 413, body: "Payload too large", contentType: "text/plain")
                    return
                }
                self.receiveAll(connection: connection, buffer: next)
            case .ready(let request):
                self.processRequest(request, connection: connection)
            case .badRequest(let message):
                self.respond(connection: connection, status: 400, body: message, contentType: "text/plain")
            }
        }
    }

    private struct ParsedHTTP {
        var method: String
        var path: String
        var headers: [String: String]
        var body: Data
    }

    private enum ParseOutcome {
        case needMore
        case ready(ParsedHTTP)
        case badRequest(String)
    }

    private func tryParseHTTP(_ data: Data, isComplete: Bool) -> ParseOutcome {
        guard let headerEnd = findHeaderEnd(in: data) else {
            return isComplete ? .badRequest("Incomplete request") : .needMore
        }
        let headerData = data.subdata(in: 0..<headerEnd)
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return .badRequest("Invalid request headers")
        }

        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else { return .badRequest("Missing request line") }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return .badRequest("Malformed request line") }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let method = String(parts[0])
        let bodyStart = headerEnd + 4 // \r\n\r\n
        let limit = maxBodyBytes()
        let contentLength: Int
        if let raw = headers["content-length"] {
            guard let parsed = Int(raw), parsed >= 0, parsed <= limit else {
                return .badRequest("Invalid Content-Length")
            }
            contentLength = parsed
        } else if methodHasBody(method) {
            // No Content-Length — wait until the connection finishes, then take remainder.
            guard isComplete else { return .needMore }
            let available = max(0, data.count - bodyStart)
            guard available <= limit else {
                return .badRequest("Payload too large")
            }
            contentLength = available
        } else {
            contentLength = 0
        }

        let available = data.count - bodyStart
        guard available >= contentLength else { return .needMore }

        let body: Data
        if contentLength > 0 {
            body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        } else {
            body = Data()
        }

        return .ready(ParsedHTTP(
            method: method,
            path: String(parts[1]),
            headers: headers,
            body: body
        ))
    }

    private func findHeaderEnd(in data: Data) -> Int? {
        let pattern: [UInt8] = [13, 10, 13, 10] // \r\n\r\n
        if data.count < pattern.count { return nil }
        for i in 0...(data.count - pattern.count) {
            if data[i] == pattern[0],
               data[i + 1] == pattern[1],
               data[i + 2] == pattern[2],
               data[i + 3] == pattern[3] {
                return i
            }
        }
        return nil
    }

    private func methodHasBody(_ method: String) -> Bool {
        method == "POST" || method == "PUT" || method == "PATCH"
    }

    private func processRequest(_ request: ParsedHTTP, connection: NWConnection) {
        fputs("Redline receiver \(request.method) \(request.path) (\(request.body.count) bytes)\n", stderr)

        if !authorized(headers: request.headers) {
            respond(connection: connection, status: 401, body: "Unauthorized", contentType: "text/plain")
            return
        }

        if request.method == "GET" && request.path == RedlinePaths.healthRoute {
            respond(connection: connection, status: 200, body: "ok", contentType: "text/plain")
            return
        }

        if request.method == "GET" && request.path == RedlinePaths.inboxRoute {
            if let json = inboxProvider() {
                respond(connection: connection, status: 200, body: String(data: json, encoding: .utf8) ?? "[]", contentType: "application/json")
            } else {
                respond(connection: connection, status: 200, body: "[]", contentType: "application/json")
            }
            return
        }

        if (request.method == "POST" || request.method == "PATCH"),
           let itemId = RedlinePaths.inboxStatusItemId(from: request.path) {
            guard let inboxStatusHandler else {
                respond(connection: connection, status: 501, body: "Status updates not enabled", contentType: "text/plain")
                return
            }
            struct StatusBody: Decodable {
                var status: String
                var summary: String?
            }
            do {
                let decoded = try JSONDecoder().decode(StatusBody.self, from: request.body)
                Task {
                    let result = await inboxStatusHandler(itemId, decoded.status, decoded.summary)
                    self.respond(
                        connection: connection,
                        status: result.statusCode,
                        body: result.body,
                        contentType: "application/json"
                    )
                }
            } catch {
                respond(
                    connection: connection,
                    status: 422,
                    body: "{\"ok\":false,\"error\":\"Invalid JSON — need {\\\"status\\\":\\\"applied|failed|pending|agent_running\\\",\\\"summary\\\":\\\"…\\\"}\"}",
                    contentType: "application/json"
                )
            }
            return
        }

        guard request.method == "POST", request.path == RedlinePaths.feedbackRoute else {
            respond(connection: connection, status: 404, body: "Not found", contentType: "text/plain")
            return
        }

        if request.body.count > maxBodyBytes() {
            respond(connection: connection, status: 413, body: "Payload too large", contentType: "text/plain")
            return
        }

        do {
            let payload = try FeedbackPayload.decode(from: request.body)
            try payload.validateForIngest()
            Task {
                do {
                    try await self.handler(payload)
                    fputs("Redline receiver stored feedback \(payload.screen)/\(payload.region)\n", stderr)
                    self.respond(connection: connection, status: 200, body: "{\"ok\":true}", contentType: "application/json")
                } catch {
                    fputs("Redline receiver store error: \(error.localizedDescription)\n", stderr)
                    self.respond(
                        connection: connection,
                        status: 500,
                        body: "{\"ok\":false,\"error\":\"Bundle write failed\"}",
                        contentType: "application/json"
                    )
                }
            }
        } catch {
            fputs("Redline receiver decode error: \(error.localizedDescription)\n", stderr)
            respond(connection: connection, status: 422, body: error.localizedDescription, contentType: "text/plain")
        }
    }

    private func authorized(headers: [String: String]) -> Bool {
        guard let expected = authToken(), !expected.isEmpty else { return true }
        guard let value = headers["authorization"] else { return false }
        let prefix = "bearer "
        guard value.lowercased().hasPrefix(prefix) else { return false }
        let provided = String(value.dropFirst(prefix.count))
        let a = Array(provided.utf8)
        let b = Array(expected.utf8)
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in a.indices {
            diff |= a[i] ^ b[i]
        }
        return diff == 0
    }

    private func respond(connection: NWConnection, status: Int, body: String, contentType: String) {
        let response = """
        HTTP/1.1 \(status) \(HTTPURLResponse.localizedString(forStatusCode: status))\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
