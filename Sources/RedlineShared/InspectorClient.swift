import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Client for the optional iOS hierarchy TCP service (`inspect` / `redline_get_tree`).
public final class InspectorClient: @unchecked Sendable {
    public var connectionTimeout: TimeInterval = 1.5

    public init() {}

    public func ping(host: String = "127.0.0.1", port: UInt16) async throws -> InspectableAppInfo {
        let response = try await send(request: InspectorRequest(type: .ping), host: host, port: port)
        guard response.ok, let app = response.app else {
            throw InspectorClientError.requestFailed(response.error ?? "ping failed")
        }
        return app
    }

    public func fetchHierarchy(
        host: String = "127.0.0.1",
        port: UInt16,
        options: HierarchyCaptureOptions = .default
    ) async throws -> HierarchySnapshot {
        let previous = connectionTimeout
        connectionTimeout = options.includeScreenshots ? 45 : 8
        defer { connectionTimeout = previous }
        let response = try await send(
            request: InspectorRequest(type: .hierarchy, captureOptions: options),
            host: host,
            port: port
        )
        guard response.ok, let hierarchy = response.hierarchy else {
            throw InspectorClientError.requestFailed(response.error ?? "hierarchy failed")
        }
        return hierarchy
    }

    public func refreshNode(
        nodeId: String,
        host: String = "127.0.0.1",
        port: UInt16,
        options: HierarchyCaptureOptions = .default
    ) async throws -> HierarchySnapshot {
        let response = try await send(
            request: InspectorRequest(type: .refreshNode, nodeId: nodeId, captureOptions: options),
            host: host,
            port: port
        )
        guard response.ok, let hierarchy = response.hierarchy else {
            throw InspectorClientError.requestFailed(response.error ?? "refreshNode failed")
        }
        return hierarchy
    }

    public func console(
        nodeId: String,
        expression: String,
        host: String = "127.0.0.1",
        port: UInt16
    ) async throws -> String {
        let response = try await send(
            request: InspectorRequest(type: .console, nodeId: nodeId, attributeValue: expression),
            host: host,
            port: port
        )
        guard response.ok, let output = response.consoleOutput else {
            throw InspectorClientError.requestFailed(response.error ?? "console failed")
        }
        return output
    }

    public func fetchAttributes(nodeId: String, host: String = "127.0.0.1", port: UInt16) async throws -> NodeAttributes {
        let response = try await send(
            request: InspectorRequest(type: .attributes, nodeId: nodeId),
            host: host,
            port: port
        )
        guard response.ok, let attributes = response.attributes else {
            throw InspectorClientError.requestFailed(response.error ?? "attributes failed")
        }
        return attributes
    }

    public func setAttribute(
        nodeId: String,
        key: String,
        value: String,
        host: String = "127.0.0.1",
        port: UInt16
    ) async throws {
        let response = try await send(
            request: InspectorRequest(
                type: .setAttribute,
                nodeId: nodeId,
                attributeKey: key,
                attributeValue: value
            ),
            host: host,
            port: port
        )
        guard response.ok else {
            throw InspectorClientError.requestFailed(response.error ?? "setAttribute failed")
        }
    }

    public func measure(from: String, to: String, host: String = "127.0.0.1", port: UInt16) async throws -> MeasuredGap {
        let response = try await send(
            request: InspectorRequest(type: .measure, nodeId: from, nodeIdB: to),
            host: host,
            port: port
        )
        guard response.ok, let gap = response.measuredGap else {
            throw InspectorClientError.requestFailed(response.error ?? "measure failed")
        }
        return gap
    }

    public func snapshotPNGBase64(nodeId: String, host: String = "127.0.0.1", port: UInt16) async throws -> String {
        let previous = connectionTimeout
        connectionTimeout = 8
        defer { connectionTimeout = previous }
        let response = try await send(
            request: InspectorRequest(type: .snapshot, nodeId: nodeId),
            host: host,
            port: port
        )
        guard response.ok, let png = response.pngBase64 else {
            throw InspectorClientError.requestFailed(response.error ?? "snapshot failed")
        }
        return png
    }

    public func highlight(nodeId: String, host: String = "127.0.0.1", port: UInt16) async throws {
        _ = try await send(
            request: InspectorRequest(type: .highlight, nodeId: nodeId),
            host: host,
            port: port
        )
    }

    public func startRedline(bridge: StartRedlineBridge, host: String = "127.0.0.1", port: UInt16) async throws {
        _ = try await send(
            request: InspectorRequest(type: .startRedline, bridge: bridge),
            host: host,
            port: port
        )
    }

    private func send(request: InspectorRequest, host: String, port: UInt16) async throws -> InspectorResponse {
        // Prefer IPv4 loopback — matches RedlineServer's POSIX IPv4 bind.
        let hosts: [String]
        if host == "127.0.0.1" || host == "localhost" || host == "::1" {
            hosts = ["127.0.0.1", "::1"]
        } else {
            hosts = [host]
        }
        var lastError: Error = InspectorClientError.disconnected
        for candidate in hosts {
            do {
                return try await sendOnce(request: request, host: candidate, port: port)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func sendOnce(request: InspectorRequest, host: String, port: UInt16) async throws -> InspectorResponse {
        try await withThrowingTaskGroup(of: InspectorResponse.self) { group in
            group.addTask {
                try await self.performSendPOSIX(request: request, host: host, port: port)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(self.connectionTimeout * 1_000_000_000))
                throw InspectorClientError.timeout
            }
            do {
                guard let result = try await group.next() else {
                    throw InspectorClientError.disconnected
                }
                group.cancelAll()
                return result
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    /// BSD sockets — avoids Network.framework Local Network / loopback quirks in .app targets.
    private func performSendPOSIX(request: InspectorRequest, host: String, port: UInt16) async throws -> InspectorResponse {
        let timeout = connectionTimeout
        return try await Task.detached(priority: .userInitiated) {
            let payload = try WireCodec.encode(request)
            let fd = try Self.connectPOSIX(host: host, port: port, timeout: timeout)
            defer { close(fd) }

            try Self.writeAll(fd: fd, data: payload)

            var buffer = Data()
            var scratch = [UInt8](repeating: 0, count: 64 * 1024)
            let deadline = Date().addingTimeInterval(timeout)

            while Date() < deadline {
                if Task.isCancelled { throw InspectorClientError.disconnected }

                var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let remaining = deadline.timeIntervalSinceNow
                let ms = max(1, Int32(remaining * 1000))
                let pr = poll(&pfd, 1, ms)
                if pr == 0 { throw InspectorClientError.timeout }
                if pr < 0 {
                    if errno == EINTR { continue }
                    throw InspectorClientError.requestFailed("poll failed errno=\(errno)")
                }

                let n = read(fd, &scratch, scratch.count)
                if n > 0 {
                    buffer.append(contentsOf: scratch[0 ..< n])
                    if let response: InspectorResponse = try WireCodec.decodeOne(InspectorResponse.self, from: &buffer) {
                        return response
                    }
                } else if n == 0 {
                    throw InspectorClientError.disconnected
                } else if errno != EAGAIN && errno != EWOULDBLOCK {
                    throw InspectorClientError.requestFailed("read failed errno=\(errno)")
                }
            }
            throw InspectorClientError.timeout
        }.value
    }

    private static func connectPOSIX(host: String, port: UInt16, timeout: TimeInterval) throws -> Int32 {
        let isV6 = host.contains(":")
        let fd = socket(isV6 ? AF_INET6 : AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else {
            throw InspectorClientError.requestFailed("socket() failed")
        }

        var nosig: Int32 = 1
        #if !os(Linux)
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosig, socklen_t(MemoryLayout<Int32>.size))
        #endif

        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        let connectResult: Int32
        if isV6 {
            var addr = sockaddr_in6()
            addr.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            addr.sin6_family = sa_family_t(AF_INET6)
            addr.sin6_port = port.bigEndian
            guard host.withCString({ inet_pton(AF_INET6, $0, &addr.sin6_addr) == 1 }) else {
                close(fd)
                throw InspectorClientError.requestFailed("invalid IPv6 host \(host)")
            }
            connectResult = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            }
        } else {
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            guard host.withCString({ inet_pton(AF_INET, $0, &addr.sin_addr) == 1 }) else {
                close(fd)
                throw InspectorClientError.requestFailed("invalid IPv4 host \(host)")
            }
            connectResult = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        if connectResult != 0 {
            guard errno == EINPROGRESS else {
                let err = errno
                close(fd)
                throw InspectorClientError.requestFailed("connect failed errno=\(err)")
            }

            var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let ms = max(1, Int32(timeout * 1000))
            let pr = poll(&pfd, 1, ms)
            if pr == 0 {
                close(fd)
                throw InspectorClientError.timeout
            }
            if pr < 0 {
                let err = errno
                close(fd)
                throw InspectorClientError.requestFailed("poll failed errno=\(err)")
            }

            var soError: Int32 = 0
            var len = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &len)
            guard soError == 0 else {
                close(fd)
                throw InspectorClientError.requestFailed("connect failed errno=\(soError)")
            }
        }

        _ = fcntl(fd, F_SETFL, flags)
        return fd
    }

    private static func writeAll(fd: Int32, data: Data) throws {
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else {
                throw InspectorClientError.requestFailed("empty payload")
            }
            var sent = 0
            let total = raw.count
            while sent < total {
                let n = write(fd, base.advanced(by: sent), total - sent)
                if n <= 0 {
                    throw InspectorClientError.requestFailed("write failed errno=\(errno)")
                }
                sent += n
            }
        }
    }
}

public enum InspectorClientError: Error, LocalizedError {
    case requestFailed(String)
    case disconnected
    case timeout

    public var errorDescription: String? {
        switch self {
        case .requestFailed(let message): return message
        case .disconnected: return "Inspector connection closed"
        case .timeout: return "Inspector connection timed out"
        }
    }
}
