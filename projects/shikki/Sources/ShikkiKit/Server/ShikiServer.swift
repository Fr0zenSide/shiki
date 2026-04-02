import Foundation
import Network
import Logging

/// Embedded HTTP server replacing the Deno/TypeScript backend.
///
/// Uses Apple's Network framework (`NWListener`) for zero external dependencies.
/// Serves the same API surface that `BackendClient` calls via curl, so the CLI
/// can work without Docker or Deno.
///
/// Usage:
/// ```swift
/// let server = ShikiServer(port: 3900)
/// try await server.start()
/// // ... server is running ...
/// server.stop()
/// ```
public final class ShikiServer: Sendable {
    private let requestedPort: Int
    private let store: InMemoryStore
    private let routes: ServerRoutes
    private let logger: Logger

    // NWListener and state stored behind a lock for Sendable compliance
    private let state: ServerState

    /// Thread-safe mutable state container.
    private final class ServerState: @unchecked Sendable {
        private let lock = NSLock()
        private var _listener: NWListener?
        private var _actualPort: Int = 0
        private var _connections: Set<NWConnectionWrapper> = []

        var listener: NWListener? {
            get { lock.withLock { _listener } }
            set { lock.withLock { _listener = newValue } }
        }

        var actualPort: Int {
            get { lock.withLock { _actualPort } }
            set { lock.withLock { _actualPort = newValue } }
        }

        func addConnection(_ conn: NWConnectionWrapper) {
            lock.withLock { _ = _connections.insert(conn) }
        }

        func removeConnection(_ conn: NWConnectionWrapper) {
            lock.withLock { _ = _connections.remove(conn) }
        }

        func cancelAllConnections() {
            lock.withLock {
                for conn in _connections {
                    conn.connection.cancel()
                }
                _connections.removeAll()
            }
        }
    }

    /// Wrapper to make NWConnection usable in a Set.
    private final class NWConnectionWrapper: Hashable, @unchecked Sendable {
        let connection: NWConnection
        let id = UUID()

        init(_ connection: NWConnection) {
            self.connection = connection
        }

        static func == (lhs: NWConnectionWrapper, rhs: NWConnectionWrapper) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    /// The port the server is actually listening on (may differ from requested if 0 was used).
    public var actualPort: Int {
        state.actualPort
    }

    public init(port: Int = 3900, logger: Logger = Logger(label: "shikki.server")) {
        self.requestedPort = port
        self.store = InMemoryStore()
        self.routes = ServerRoutes(store: store)
        self.logger = logger
        self.state = ServerState()
    }

    /// Start the HTTP server. Returns after the listener is ready.
    public func start() async throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let listener: NWListener
        if requestedPort == 0 {
            listener = try NWListener(using: parameters)
        } else {
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: UInt16(requestedPort)))
        }

        state.listener = listener

        let serverState = self.state
        let serverLogger = self.logger
        let serverSelf = self

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Use an atomic-like class to track if we already resumed
            let resumeGuard = ResumeGuard(continuation: continuation)

            listener.stateUpdateHandler = { newState in
                switch newState {
                case .ready:
                    if let port = listener.port {
                        serverState.actualPort = Int(port.rawValue)
                        serverLogger.info("ShikiServer listening on port \(port.rawValue)")
                    }
                    resumeGuard.resume(with: .success(()))
                case .failed(let error):
                    serverLogger.error("ShikiServer failed: \(error)")
                    resumeGuard.resume(with: .failure(error))
                case .cancelled:
                    break
                default:
                    break
                }
            }

            listener.newConnectionHandler = { connection in
                serverSelf.handleConnection(connection)
            }

            listener.start(queue: .global(qos: .userInitiated))
        }
    }

    /// Stop the server and cancel all connections.
    public func stop() {
        state.cancelAllConnections()
        state.listener?.cancel()
        state.listener = nil
        logger.info("ShikiServer stopped")
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        let wrapper = NWConnectionWrapper(connection)
        state.addConnection(wrapper)

        connection.stateUpdateHandler = { [weak self] newState in
            switch newState {
            case .ready:
                self?.receiveHTTPRequest(connection: connection, wrapper: wrapper)
            case .failed, .cancelled:
                self?.state.removeConnection(wrapper)
            default:
                break
            }
        }

        connection.start(queue: .global(qos: .userInitiated))
    }

    private func receiveHTTPRequest(connection: NWConnection, wrapper: NWConnectionWrapper) {
        // Accumulate data in a buffer for multi-chunk reads
        let buffer = DataBuffer()
        receiveChunk(connection: connection, wrapper: wrapper, buffer: buffer)
    }

    /// Accumulate data chunks until we have a complete HTTP request.
    private func receiveChunk(connection: NWConnection, wrapper: NWConnectionWrapper, buffer: DataBuffer) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] content, _, isComplete, error in
            guard let self else { return }

            if let error {
                self.logger.debug("Receive error: \(error)")
                connection.cancel()
                self.state.removeConnection(wrapper)
                return
            }

            if let data = content {
                buffer.append(data)
            }

            let accumulated = buffer.data

            // Check if we have the full HTTP request by looking for Content-Length
            if let headerEnd = self.findHeaderEnd(in: accumulated) {
                let headerData = accumulated[..<headerEnd]
                let contentLength = self.parseContentLength(from: headerData)
                let bodyStart = headerEnd + 4 // skip \r\n\r\n
                let bodyReceived = accumulated.count - bodyStart

                if bodyReceived >= contentLength {
                    // We have the complete request
                    self.processRequest(data: accumulated, connection: connection, wrapper: wrapper)
                    return
                }
                // Need more data for the body
            }

            if isComplete {
                // Connection closed, process whatever we have
                if !accumulated.isEmpty {
                    self.processRequest(data: accumulated, connection: connection, wrapper: wrapper)
                } else {
                    connection.cancel()
                    self.state.removeConnection(wrapper)
                }
                return
            }

            // Need more data — read again
            self.receiveChunk(connection: connection, wrapper: wrapper, buffer: buffer)
        }
    }

    /// Find the byte offset of the \r\n\r\n header separator.
    private func findHeaderEnd(in data: Data) -> Int? {
        let separator: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A] // \r\n\r\n
        guard data.count >= 4 else { return nil }
        for i in 0...(data.count - 4) {
            if data[data.startIndex + i] == separator[0] &&
               data[data.startIndex + i + 1] == separator[1] &&
               data[data.startIndex + i + 2] == separator[2] &&
               data[data.startIndex + i + 3] == separator[3] {
                return i
            }
        }
        return nil
    }

    /// Extract Content-Length value from raw header bytes.
    private func parseContentLength(from headerData: Data) -> Int {
        guard let headerString = String(data: headerData, encoding: .utf8) else { return 0 }
        let lines = headerString.split(separator: "\r\n")
        for line in lines {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                return Int(value) ?? 0
            }
        }
        return 0
    }

    private func processRequest(data: Data, connection: NWConnection, wrapper: NWConnectionWrapper) {
        let request = self.parseHTTPRequest(data: data)

        Task {
            let (statusCode, responseBody) = await self.routes.handle(
                method: request.method,
                path: request.path,
                body: request.body
            )

            let httpResponse = self.buildHTTPResponse(
                statusCode: statusCode,
                body: responseBody
            )

            connection.send(content: httpResponse, completion: .contentProcessed { _ in
                connection.cancel()
                self.state.removeConnection(wrapper)
            })
        }
    }

    /// Thread-safe data accumulator for multi-chunk HTTP reads.
    private final class DataBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var _data = Data()

        var data: Data {
            lock.withLock { _data }
        }

        func append(_ chunk: Data) {
            lock.lock()
            _data.append(chunk)
            lock.unlock()
        }
    }

    // MARK: - HTTP Parsing

    private struct HTTPRequest {
        let method: String
        let path: String
        let headers: [(String, String)]
        let body: Data?
    }

    private func parseHTTPRequest(data: Data) -> HTTPRequest {
        guard let requestString = String(data: data, encoding: .utf8) else {
            return HTTPRequest(method: "GET", path: "/", headers: [], body: nil)
        }

        // Split headers from body
        let parts = requestString.components(separatedBy: "\r\n\r\n")
        let headerSection = parts[0]
        let bodyString = parts.count > 1 ? parts[1...].joined(separator: "\r\n\r\n") : nil

        let lines = headerSection.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        guard let requestLine = lines.first else {
            return HTTPRequest(method: "GET", path: "/", headers: [], body: nil)
        }

        // Parse request line: "GET /path HTTP/1.1"
        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        let method = requestParts.count > 0 ? requestParts[0] : "GET"
        let path = requestParts.count > 1 ? requestParts[1] : "/"

        // Parse headers
        var headers: [(String, String)] = []
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            let headerParts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if headerParts.count == 2 {
                headers.append((headerParts[0], headerParts[1]))
            }
        }

        // Parse body using Content-Length
        var body: Data?
        if let bodyString, !bodyString.isEmpty {
            let contentLength = headers
                .first { $0.0.lowercased() == "content-length" }
                .flatMap { Int($0.1) }

            if let contentLength {
                let bodyData = Data(bodyString.utf8)
                body = bodyData.prefix(contentLength)
            } else {
                body = Data(bodyString.utf8)
            }
        }

        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }

    // MARK: - HTTP Response Building

    private func buildHTTPResponse(statusCode: Int, body: Data) -> Data {
        let statusText = Self.httpStatusText(statusCode)
        var response = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
        response += "Content-Type: application/json\r\n"
        response += "Content-Length: \(body.count)\r\n"
        response += "Connection: close\r\n"
        response += "Access-Control-Allow-Origin: *\r\n"
        response += "\r\n"

        var data = Data(response.utf8)
        data.append(body)
        return data
    }

    /// Thread-safe one-shot continuation guard.
    private final class ResumeGuard: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Error>?

        init(continuation: CheckedContinuation<Void, Error>) {
            self.continuation = continuation
        }

        func resume(with result: Result<Void, Error>) {
            lock.lock()
            let cont = continuation
            continuation = nil
            lock.unlock()
            cont?.resume(with: result)
        }
    }

    private static func httpStatusText(_ code: Int) -> String {
        switch code {
        case 200: "OK"
        case 201: "Created"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 500: "Internal Server Error"
        default: "Unknown"
        }
    }
}
