import Foundation
import Logging

// MARK: - Errors

enum ShikkiDBError: Error, Sendable, CustomStringConvertible {
    case httpError(statusCode: Int, body: String)
    case connectionRefused(underlying: String)
    case invalidURL(String)
    case decodingError(String)
    case unexpectedError(String)
    case retriesExhausted(lastError: String, attempts: Int)

    var description: String {
        switch self {
        case .httpError(let code, let body):
            return "HTTP \(code): \(body)"
        case .connectionRefused(let underlying):
            return "Connection refused — is ShikkiDB running? (\(underlying))"
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .decodingError(let detail):
            return "Decoding error: \(detail)"
        case .unexpectedError(let detail):
            return "Unexpected error: \(detail)"
        case .retriesExhausted(let lastError, let attempts):
            return "Retries exhausted after \(attempts) attempts — last error: \(lastError)"
        }
    }

    /// Whether this error is transient and can be retried
    var isTransient: Bool {
        switch self {
        case .connectionRefused:
            return true
        case .httpError(let code, _):
            return code >= 500 || code == 429
        case .retriesExhausted:
            return false
        case .invalidURL, .decodingError, .unexpectedError:
            return false
        }
    }
}

// MARK: - Protocol for testability

protocol ShikkiDBClientProtocol: Sendable {
    func dataSyncWrite(type: String, scope: String, data: [String: JSONValue], projectId: String?) async throws -> JSONValue
    func memoriesSearch(query: String, projectIds: [String]?, types: [String]?, limit: Int) async throws -> JSONValue
    func healthCheck() async throws -> Bool
}

// MARK: - Retry Configuration

struct RetryConfig: Sendable {
    let maxAttempts: Int
    let baseDelayMs: UInt64
    let maxDelayMs: UInt64

    static let `default` = RetryConfig(maxAttempts: 3, baseDelayMs: 200, maxDelayMs: 2000)
    static let none = RetryConfig(maxAttempts: 1, baseDelayMs: 0, maxDelayMs: 0)

    func delay(forAttempt attempt: Int) -> UInt64 {
        guard attempt > 0 else { return 0 }
        let exponential = baseDelayMs * UInt64(1 << min(attempt - 1, 5))
        return min(exponential, maxDelayMs)
    }
}

// MARK: - ShikkiDBClient

actor ShikkiDBClient: ShikkiDBClientProtocol {
    let baseURL: String
    let retryConfig: RetryConfig
    private let logger = Logger(label: "shikki.mcp.db-client")
    private let session: URLSession

    init(baseURL: String = "http://localhost:3900", retryConfig: RetryConfig = .default) {
        self.baseURL = baseURL
        self.retryConfig = retryConfig
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
    }

    func dataSyncWrite(type: String, scope: String, data: [String: JSONValue], projectId: String? = nil) async throws -> JSONValue {
        let url = try buildURL("/api/data-sync")

        var payloadDict: [String: JSONValue] = [
            "type": .string(type),
            "scope": .string(scope),
            "data": .object(data),
        ]
        if let pid = projectId ?? Self.resolveProjectId(scope) {
            payloadDict["projectId"] = .string(pid)
        }
        let payload: JSONValue = .object(payloadDict)

        let responseData = try await postWithRetry(url: url, body: payload)
        return try decodeJSON(responseData)
    }

    func memoriesSearch(query: String, projectIds: [String]?, types: [String]?, limit: Int) async throws -> JSONValue {
        let url = try buildURL("/api/memories/search")

        var body: [String: JSONValue] = [
            "query": .string(query),
            "limit": .int(limit),
        ]

        if let projectIds = projectIds, !projectIds.isEmpty {
            body["projectIds"] = .array(projectIds.map { .string($0) })
        }

        if let types = types, !types.isEmpty {
            body["types"] = .array(types.map { .string($0) })
        }

        let responseData = try await postWithRetry(url: url, body: .object(body))
        return try decodeJSON(responseData)
    }

    func healthCheck() async throws -> Bool {
        let url = try buildURL("/health")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Project ID Resolution

    /// Resolve project name to UUID. Known projects are hardcoded for now.
    /// Future: query the DB for project list and cache.
    static func resolveProjectId(_ projectName: String) -> String? {
        let knownProjects: [String: String] = [
            "shiki": "80c27043-5282-4814-b79d-5e6d3903cbc9",
            "shikki": "80c27043-5282-4814-b79d-5e6d3903cbc9",
            "maya": "bb9e4385-f087-4f65-8251-470f14230c3c",
            "research": "1b6da95d-6a93-4048-a975-f20e7885e669",
        ]
        return knownProjects[projectName.lowercased()]
    }

    // MARK: - Retry Logic

    private func postWithRetry(url: URL, body: JSONValue) async throws -> Data {
        var lastError: ShikkiDBError?

        for attempt in 0..<retryConfig.maxAttempts {
            if attempt > 0 {
                let delayMs = retryConfig.delay(forAttempt: attempt)
                logger.info("Retrying request (attempt \(attempt + 1)/\(retryConfig.maxAttempts)) after \(delayMs)ms")
                try await Task.sleep(nanoseconds: delayMs * 1_000_000)
            }

            do {
                return try await post(url: url, body: body)
            } catch let error as ShikkiDBError {
                lastError = error
                if !error.isTransient {
                    throw error
                }
                logger.warning("Transient error on attempt \(attempt + 1): \(error.description)")
            }
        }

        // If only 1 attempt was configured, re-throw the original error directly
        if retryConfig.maxAttempts <= 1, let lastError {
            throw lastError
        }

        throw ShikkiDBError.retriesExhausted(
            lastError: lastError?.description ?? "unknown",
            attempts: retryConfig.maxAttempts
        )
    }

    // MARK: - Private

    private func buildURL(_ path: String) throws -> URL {
        guard let url = URL(string: baseURL + path) else {
            throw ShikkiDBError.invalidURL(baseURL + path)
        }
        return url
    }

    private func post(url: URL, body: JSONValue) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            if urlError.code == .cannotConnectToHost || urlError.code == .networkConnectionLost || urlError.code == .timedOut {
                throw ShikkiDBError.connectionRefused(underlying: urlError.localizedDescription)
            }
            throw ShikkiDBError.unexpectedError(urlError.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ShikkiDBError.unexpectedError("Non-HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8) ?? "<undecodable>"
            throw ShikkiDBError.httpError(statusCode: httpResponse.statusCode, body: bodyString)
        }

        return data
    }

    private func decodeJSON(_ data: Data) throws -> JSONValue {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(JSONValue.self, from: data)
        } catch {
            throw ShikkiDBError.decodingError(error.localizedDescription)
        }
    }
}
