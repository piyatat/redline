#if os(iOS)
import Foundation
import Network
import RedlineShared

/// Optional hierarchy TCP for CLI `inspect` / MCP `redline_get_tree` (not used by designer Send).
public final class InspectorTCPService: @unchecked Sendable {
    public static let shared = InspectorTCPService()

    private var listener: NWListener?
    private var ipv4Socket: Int32 = -1
    private let queue = DispatchQueue(label: "dev.redline.inspector-tcp")
    private var acceptSource: DispatchSourceRead?
    public private(set) var boundPort: UInt16?

    private init() {}

    public func start(port: UInt16 = UInt16(RedlinePorts.simulatorInspectStart)) {
        guard listener == nil, acceptSource == nil else { return }

        let ports = Array(port ... UInt16(RedlinePorts.simulatorInspectEnd))
            + Array(UInt16(RedlinePorts.usbInspectStart) ... UInt16(RedlinePorts.usbInspectEnd))

        for candidate in ports {
            // Prefer POSIX IPv4 — NWListener on Simulator often binds IPv6-only.
            if bindIPv4(port: candidate) {
                return
            }
            if bindNetworkFramework(port: candidate) {
                return
            }
        }
        fputs("Redline inspector failed to bind any port in \(ports.first!)–\(ports.last!)\n", stderr)
    }

    public func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        if ipv4Socket >= 0 {
            close(ipv4Socket)
            ipv4Socket = -1
        }
        listener?.cancel()
        listener = nil
        boundPort = nil
    }

    /// BSD IPv4 listen on 127.0.0.1 — Mac reaches Simulator / USB-forwarded device via loopback; not exposed on LAN.
    @discardableResult
    private func bindIPv4(port: UInt16) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return false }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        #if !os(Linux)
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &reuse, socklen_t(MemoryLayout<Int32>.size))
        #endif

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            return false
        }
        guard listen(fd, 16) == 0 else {
            close(fd)
            return false
        }

        ipv4Socket = fd
        boundPort = port

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptIPv4Client()
        }
        source.setCancelHandler {
            // socket closed in stop()
        }
        acceptSource = source
        source.resume()
        fputs("Redline inspector listening on 127.0.0.1:\(port) (IPv4)\n", stderr)
        return true
    }

    private func acceptIPv4Client() {
        var addr = sockaddr_storage()
        var len = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let clientFD = withUnsafeMutablePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                accept(ipv4Socket, sockPtr, &len)
            }
        }
        guard clientFD >= 0 else { return }
        handle(posixFD: clientFD)
    }

    private func handle(posixFD: Int32) {
        queue.async {
            var buffer = Data()
            var scratch = [UInt8](repeating: 0, count: 64 * 1024)

            func respond(_ response: InspectorResponse) {
                guard let payload = try? WireCodec.encode(response) else { return }
                payload.withUnsafeBytes { raw in
                    var sent = 0
                    let total = raw.count
                    while sent < total {
                        let n = write(posixFD, raw.baseAddress!.advanced(by: sent), total - sent)
                        if n <= 0 { return }
                        sent += n
                    }
                }
            }

            while true {
                let n = read(posixFD, &scratch, scratch.count)
                if n <= 0 {
                    close(posixFD)
                    return
                }
                buffer.append(contentsOf: scratch[0 ..< n])

                while let request: InspectorRequest = try? WireCodec.decodeOne(InspectorRequest.self, from: &buffer) {
                    respond(Self.handle(request: request))
                }
            }
        }
    }

    @discardableResult
    private func bindNetworkFramework(port: UInt16) -> Bool {
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.includePeerToPeer = false
            if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
                ip.version = .v4
            }
            let nwPort = NWEndpoint.Port(rawValue: port)!
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: nwPort)
            let listener = try NWListener(using: parameters)
            self.listener = listener
            self.boundPort = port

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    fputs("Redline inspector NWListener ready on 127.0.0.1:\(port)\n", stderr)
                case .failed(let error):
                    fputs("Redline inspector NWListener failed on \(port): \(error)\n", stderr)
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection: connection)
            }
            listener.start(queue: queue)
            return true
        } catch {
            fputs("Redline inspector NWListener could not bind \(port): \(error)\n", stderr)
            listener = nil
            boundPort = nil
            return false
        }
    }

    private func handle(connection: NWConnection) {
        var buffer = Data()
        connection.start(queue: queue)

        func pump() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 1024) { data, _, isComplete, error in
                if let data, !data.isEmpty {
                    buffer.append(data)
                }

                while let request: InspectorRequest = try? WireCodec.decodeOne(InspectorRequest.self, from: &buffer) {
                    let response = Self.handle(request: request)
                    guard let payload = try? WireCodec.encode(response) else { continue }
                    connection.send(content: payload, completion: .contentProcessed { _ in
                        pump()
                    })
                    return
                }

                if error != nil || isComplete {
                    connection.cancel()
                } else {
                    pump()
                }
            }
        }
        pump()
    }

    private static func handle(request: InspectorRequest) -> InspectorResponse {
        switch request.type {
        case .ping:
            let app = InspectableAppInfo(
                bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown",
                appName: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "App"
            )
            return InspectorResponse(id: request.id, ok: true, app: app)

        case .hierarchy:
            let options = request.captureOptions ?? .default
            var snapshot: HierarchySnapshot!
            DispatchQueue.main.sync {
                snapshot = CaptureEngine.captureHierarchy(options: options)
            }
            return InspectorResponse(id: request.id, ok: true, hierarchy: snapshot)

        case .refreshNode:
            guard let nodeId = request.nodeId else {
                return InspectorResponse(id: request.id, ok: false, error: "Missing nodeId")
            }
            let options = request.captureOptions ?? .default
            var snapshot: HierarchySnapshot?
            DispatchQueue.main.sync {
                snapshot = CaptureEngine.captureSubtree(nodeId: nodeId, options: options)
            }
            guard let snapshot else {
                return InspectorResponse(id: request.id, ok: false, error: "Refresh failed")
            }
            return InspectorResponse(id: request.id, ok: true, hierarchy: snapshot, refreshHint: true)

        case .console:
            guard let nodeId = request.nodeId, let expr = request.attributeValue else {
                return InspectorResponse(id: request.id, ok: false, error: "Missing console params")
            }
            var output = ""
            DispatchQueue.main.sync {
                output = ConsoleEngine.evaluate(nodeId: nodeId, expression: expr)
            }
            return InspectorResponse(id: request.id, ok: true, consoleOutput: output)

        case .snapshot:
            guard let nodeId = request.nodeId else {
                return InspectorResponse(id: request.id, ok: false, error: "Missing nodeId")
            }
            var png: String?
            DispatchQueue.main.sync {
                png = CaptureEngine.liveSnapshotPNGBase64(nodeId: nodeId)
            }
            guard let png else {
                return InspectorResponse(id: request.id, ok: false, error: "Snapshot failed")
            }
            return InspectorResponse(id: request.id, ok: true, pngBase64: png)

        case .highlight:
            if let nodeId = request.nodeId {
                DispatchQueue.main.async {
                    CaptureEngine.highlight(nodeId: nodeId)
                }
            }
            return InspectorResponse(id: request.id, ok: true)

        case .attributes:
            guard let nodeId = request.nodeId else {
                return InspectorResponse(id: request.id, ok: false, error: "Missing nodeId")
            }
            var attributes: NodeAttributes?
            DispatchQueue.main.sync {
                attributes = AttributeEngine.read(nodeId: nodeId)
            }
            guard let attributes else {
                return InspectorResponse(id: request.id, ok: false, error: "Node not found")
            }
            return InspectorResponse(id: request.id, ok: true, attributes: attributes)

        case .setAttribute:
            guard let nodeId = request.nodeId,
                  let key = request.attributeKey,
                  let value = request.attributeValue else {
                return InspectorResponse(id: request.id, ok: false, error: "Missing attribute params")
            }
            var success = false
            DispatchQueue.main.sync {
                success = AttributeEngine.write(nodeId: nodeId, key: key, value: value)
            }
            return InspectorResponse(
                id: request.id,
                ok: success,
                error: success ? nil : "setAttribute failed",
                refreshHint: success
            )

        case .measure:
            guard let fromId = request.nodeId, let toId = request.nodeIdB else {
                return InspectorResponse(id: request.id, ok: false, error: "Missing node ids")
            }
            var gap: MeasuredGap?
            DispatchQueue.main.sync {
                let hierarchy = CaptureEngine.captureHierarchy()
                guard let from = hierarchy.nodes[fromId], let to = hierarchy.nodes[toId] else { return }
                gap = RedlineBridge.measureGap(from: from, to: to)
            }
            guard let gap else {
                return InspectorResponse(id: request.id, ok: false, error: "Measure failed")
            }
            return InspectorResponse(id: request.id, ok: true, measuredGap: gap)

        case .startRedline:
            DispatchQueue.main.async {
                if let bridge = request.bridge {
                    DesignerModeController.shared.beginMarkup(fromBridge: bridge)
                } else if let region = request.nodeId {
                    DesignerModeController.shared.beginMarkup(forRegion: region)
                } else {
                    DesignerModeController.shared.toggleDesignerMode()
                }
            }
            return InspectorResponse(id: request.id, ok: true)
        }
    }
}
#endif
