import Foundation
import Logging

/// Persists lifecycle events to ShikiDB via HTTP POST.
/// Graceful degradation: if DB is unavailable, logs a warning and continues.
/// NEVER crashes. NEVER uses curl -sf.
public actor EventPersister {
    let dbURL: String
    private let logger = Logger(label: "shiki.core.event-persister")
    private let session: URLSession

    public init(dbURL: String, session: URLSession = .shared) {
        self.dbURL = dbURL
        self.session = session
    }

    /// Build a URLRequest for persisting an event. Exposed for testing.
    public func buildRequest(for event: LifecycleEventPayload) throws -> URLRequest {
        guard let url = URL(string: "\(dbURL)/api/data-sync") else {
            throw EventPersisterError.invalidURL(dbURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(event)

        return request
    }

    /// Persist an event to ShikiDB. Never throws — logs warning on failure.
    public func persist(_ event: LifecycleEventPayload) async {
        do {
            let request = try buildRequest(for: event)
            let (_, response) = try await session.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode)
            {
                logger.warning(
                    "ShikiDB returned non-success status",
                    metadata: [
                        "statusCode": "\(httpResponse.statusCode)",
                        "eventType": "\(event.type.rawValue)",
                        "featureId": "\(event.featureId)",
                    ]
                )
            }
        } catch {
            logger.warning(
                "Failed to persist event to ShikiDB — continuing",
                metadata: [
                    "error": "\(error.localizedDescription)",
                    "eventType": "\(event.type.rawValue)",
                    "featureId": "\(event.featureId)",
                ]
            )
        }
    }
}

public enum EventPersisterError: Error, Sendable {
    case invalidURL(String)
}
