import Foundation

// MARK: - MotoRemoteResolver

/// Client-side resolver that queries a remote node's Moto cache over NATS.
///
/// This is the CLIENT side of the Moto remote resolution protocol.
/// When the local cache doesn't have the answer, the resolver can query
/// a specific node by ID or broadcast to all nodes (first response wins).
///
/// Uses NATS request-reply pattern:
/// 1. Encode `MotoQueryRequest` as JSON
/// 2. Publish to `shikki.moto.query.{nodeId}` (targeted) or
///    `shikki.moto.query.available` (broadcast)
/// 3. Wait for `MotoQueryResponse` within the timeout
///
/// All communication is JSON over NATS — no direct network calls.
public actor MotoRemoteResolver {
    private let nats: any NATSClientProtocol
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Create a resolver backed by a NATS client.
    ///
    /// - Parameter nats: Connected NATS client for request-reply.
    public init(nats: any NATSClientProtocol) {
        self.nats = nats
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    // MARK: - Targeted Query

    /// Query a specific node's Moto cache.
    ///
    /// Publishes to `shikki.moto.query.{nodeId}` and waits for a response.
    ///
    /// - Parameters:
    ///   - nodeId: Target node identifier.
    ///   - tool: MCP tool name (e.g. "moto_get_type").
    ///   - args: Tool arguments as string key-value pairs.
    ///   - timeout: Maximum wait time for a response.
    /// - Returns: Raw response data (encoded `MotoQueryResponse`).
    /// - Throws: `MotoQueryError.timeout` if no response arrives,
    ///           `MotoQueryError.remoteError` if the remote node returns an error.
    public func query(
        nodeId: String,
        tool: String,
        args: [String: String],
        timeout: Duration = .seconds(5)
    ) async throws -> Data {
        let subject = MotoQuerySubjects.targeted(nodeId: nodeId)
        return try await sendRequest(subject: subject, tool: tool, args: args, timeout: timeout)
    }

    // MARK: - Broadcast Query

    /// Broadcast query to all nodes (first response wins).
    ///
    /// Publishes to `shikki.moto.query.available` and returns the first response.
    ///
    /// - Parameters:
    ///   - tool: MCP tool name (e.g. "moto_get_type").
    ///   - args: Tool arguments as string key-value pairs.
    ///   - timeout: Maximum wait time for a response.
    /// - Returns: Raw response data (encoded `MotoQueryResponse`).
    /// - Throws: `MotoQueryError.timeout` if no response arrives,
    ///           `MotoQueryError.remoteError` if the responding node returns an error.
    public func queryAny(
        tool: String,
        args: [String: String],
        timeout: Duration = .seconds(5)
    ) async throws -> Data {
        let subject = MotoQuerySubjects.available
        return try await sendRequest(subject: subject, tool: tool, args: args, timeout: timeout)
    }

    // MARK: - Internal

    private func sendRequest(
        subject: String,
        tool: String,
        args: [String: String],
        timeout: Duration
    ) async throws -> Data {
        let request = MotoQueryRequest(tool: tool, args: args)

        let requestData: Data
        do {
            requestData = try encoder.encode(request)
        } catch {
            throw MotoQueryError.encodingFailed
        }

        let reply: NATSMessage
        do {
            reply = try await nats.request(subject: subject, data: requestData, timeout: timeout)
        } catch let error as NATSClientError where error == .timeout {
            throw MotoQueryError.timeout
        } catch {
            throw MotoQueryError.timeout
        }

        // Decode to check for remote errors
        guard let response = try? decoder.decode(MotoQueryResponse.self, from: reply.data) else {
            throw MotoQueryError.decodingFailed("Failed to decode response from \(subject)")
        }

        if !response.ok, let errorMessage = response.error {
            throw MotoQueryError.remoteError(errorMessage)
        }

        // Return the full response data so callers can decode as needed
        return reply.data
    }
}
