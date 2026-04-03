import Foundation

// MARK: - MotoQueryHandler

/// Subscribes to NATS subjects for remote Moto cache queries and responds
/// by delegating to the local `MotoMCPInterface`.
///
/// This is the SERVER side of the Moto remote resolution protocol.
/// Each node runs a `MotoQueryHandler` that listens for incoming queries
/// on `shikki.moto.query.{nodeId}` (targeted) and `shikki.moto.query.available`
/// (broadcast), processes them via the local MCP interface, and publishes
/// the result back to the request's `replyTo` subject.
///
/// Query protocol uses JSON request-reply:
/// ```json
/// // Request
/// { "tool": "moto_get_type", "args": { "name": "ShikkiKernel" } }
///
/// // Success response
/// { "ok": true, "data": {...}, "nodeId": "node-1", "cacheVersion": "1.0.0" }
///
/// // Error response
/// { "ok": false, "error": "Type not found", "nodeId": "node-1", "cacheVersion": "1.0.0" }
/// ```
public actor MotoQueryHandler {
    private let nats: any NATSClientProtocol
    private let motoInterface: MotoMCPInterface
    private let nodeId: String
    private let cacheVersion: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var listenTask: Task<Void, Never>?

    /// Create a handler for remote Moto queries.
    ///
    /// - Parameters:
    ///   - nats: NATS client for subscribing and publishing.
    ///   - motoInterface: Local MCP interface to delegate queries to.
    ///   - nodeId: This node's identifier (used in subject naming).
    ///   - cacheVersion: Version string from the .moto dotfile.
    public init(
        nats: any NATSClientProtocol,
        motoInterface: MotoMCPInterface,
        nodeId: String,
        cacheVersion: String
    ) {
        self.nats = nats
        self.motoInterface = motoInterface
        self.nodeId = nodeId
        self.cacheVersion = cacheVersion
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    // MARK: - Lifecycle

    /// Start listening for remote Moto queries.
    ///
    /// Subscribes to both the targeted subject (`shikki.moto.query.{nodeId}`)
    /// and the broadcast subject (`shikki.moto.query.available`).
    public func start() {
        let targetedStream = nats.subscribe(subject: MotoQuerySubjects.targeted(nodeId: nodeId))
        let broadcastStream = nats.subscribe(subject: MotoQuerySubjects.available)

        listenTask = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { [self] in
                    for await message in targetedStream {
                        if Task.isCancelled { break }
                        await self.handleMessage(message)
                    }
                }
                group.addTask { [self] in
                    for await message in broadcastStream {
                        if Task.isCancelled { break }
                        await self.handleMessage(message)
                    }
                }
            }
        }
    }

    /// Stop listening for queries.
    public func stop() {
        listenTask?.cancel()
        listenTask = nil
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: NATSMessage) async {
        // Must have a replyTo subject for request-reply
        guard let replyTo = message.replyTo else {
            return
        }

        // Decode the query request
        guard let request = try? decoder.decode(MotoQueryRequest.self, from: message.data) else {
            await sendErrorResponse(
                replyTo: replyTo,
                error: "Failed to decode query request"
            )
            return
        }

        // Dispatch to the appropriate MCP tool
        let response = await dispatchTool(request: request)

        // Publish response to the reply subject
        if let data = try? encoder.encode(response) {
            try? await nats.publish(subject: replyTo, data: data)
        }
    }

    private func dispatchTool(request: MotoQueryRequest) async -> MotoQueryResponse {
        do {
            switch request.tool {
            case "moto_get_type":
                guard let name = request.args["name"] else {
                    return makeErrorResponse("Missing required argument: name")
                }
                let result = try motoInterface.getType(name: name)
                guard let result else {
                    return makeErrorResponse("Type not found: \(name)")
                }
                let data = try encoder.encode(result)
                return makeSuccessResponse(data: data)

            case "moto_get_protocol":
                guard let name = request.args["name"] else {
                    return makeErrorResponse("Missing required argument: name")
                }
                let result = try motoInterface.getProtocol(name: name)
                guard let result else {
                    return makeErrorResponse("Protocol not found: \(name)")
                }
                let data = try encoder.encode(result)
                return makeSuccessResponse(data: data)

            case "moto_get_pattern":
                guard let name = request.args["name"] else {
                    return makeErrorResponse("Missing required argument: name")
                }
                let result = try motoInterface.getPattern(name: name)
                guard let result else {
                    return makeErrorResponse("Pattern not found: \(name)")
                }
                let data = try encoder.encode(result)
                return makeSuccessResponse(data: data)

            case "moto_get_context":
                let scope: MotoMCPInterface.ContextScope
                if let scopeStr = request.args["scope"],
                   let parsed = MotoMCPInterface.ContextScope(rawValue: scopeStr) {
                    scope = parsed
                } else {
                    scope = .manifest
                }
                let result = try motoInterface.getContext(scope: scope)
                let data = try encoder.encode(result)
                return makeSuccessResponse(data: data)

            case "moto_get_dependency_graph":
                let result = try motoInterface.getDependencyGraph(module: request.args["module"])
                let data = try encoder.encode(result)
                return makeSuccessResponse(data: data)

            case "moto_get_api_surface":
                let result = try motoInterface.getAPISurface(module: request.args["module"])
                let data = try encoder.encode(result)
                return makeSuccessResponse(data: data)

            case "moto_validate_cache":
                let result = try motoInterface.validateCache()
                let data = try encoder.encode(result)
                return makeSuccessResponse(data: data)

            default:
                return makeErrorResponse("Unknown tool: \(request.tool)")
            }
        } catch {
            return makeErrorResponse("Tool execution failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Response Helpers

    private func makeSuccessResponse(data: Data) -> MotoQueryResponse {
        MotoQueryResponse(
            ok: true,
            data: data,
            error: nil,
            nodeId: nodeId,
            cacheVersion: cacheVersion
        )
    }

    private func makeErrorResponse(_ error: String) -> MotoQueryResponse {
        MotoQueryResponse(
            ok: false,
            data: nil,
            error: error,
            nodeId: nodeId,
            cacheVersion: cacheVersion
        )
    }

    private func sendErrorResponse(replyTo: String, error: String) async {
        let response = makeErrorResponse(error)
        if let data = try? encoder.encode(response) {
            try? await nats.publish(subject: replyTo, data: data)
        }
    }
}
