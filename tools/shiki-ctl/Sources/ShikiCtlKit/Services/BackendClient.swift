import Foundation
import Logging
import NetKit

/// HTTP client for the Shiki orchestrator backend.
///
/// Uses NetKit's `NetworkProtocol` for typed endpoints and proper HTTP error handling.
/// Replaces the previous curl-subprocess approach with URLSession-based networking
/// for connection reuse, HTTP status visibility, and testability via `MockNetworkService`.
public actor BackendClient: BackendClientProtocol {
    private let baseURL: String
    private let logger: Logger
    private let network: any NetworkProtocol

    /// Parsed host/port/scheme from the base URL for endpoint construction.
    let endpointHost: String
    let endpointPort: Int
    let endpointScheme: String

    public init(
        baseURL: String = "http://localhost:3900",
        logger: Logger = Logger(label: "shiki-ctl.backend"),
        network: any NetworkProtocol = NetworkService()
    ) {
        self.baseURL = baseURL
        self.logger = logger
        self.network = network

        // Parse baseURL into components for endpoint construction
        if let components = URLComponents(string: baseURL) {
            self.endpointHost = components.host ?? "localhost"
            self.endpointPort = components.port ?? 3900
            self.endpointScheme = components.scheme ?? "http"
        } else {
            self.endpointHost = "localhost"
            self.endpointPort = 3900
            self.endpointScheme = "http"
        }
    }

    /// No-op for backward compatibility.
    public func shutdown() async throws {}

    // MARK: - Orchestrator

    public func getStatus() async throws -> OrchestratorStatus {
        try await send(.orchestratorStatus)
    }

    public func getStaleCompanies(thresholdMinutes: Int = 5) async throws -> [Company] {
        try await send(.staleCompanies(thresholdMinutes: thresholdMinutes))
    }

    public func getReadyCompanies() async throws -> [Company] {
        try await send(.readyCompanies)
    }

    public func getDispatcherQueue() async throws -> [DispatcherTask] {
        try await send(.dispatcherQueue)
    }

    public func getDailyReport(date: String? = nil) async throws -> DailyReport {
        try await send(.dailyReport(date: date))
    }

    public func sendHeartbeat(companyId: String, sessionId: String) async throws -> HeartbeatResponse {
        try await send(.heartbeat(companyId: companyId, sessionId: sessionId))
    }

    // MARK: - Companies

    public func getCompanies(status: String? = nil) async throws -> [Company] {
        try await send(.companies(status: status))
    }

    public func patchCompany(id: String, updates: [String: Any]) async throws -> Company {
        try await send(.patchCompany(id: id, updates: updates))
    }

    // MARK: - Decisions

    public func getPendingDecisions() async throws -> [Decision] {
        try await send(.pendingDecisions)
    }

    public func answerDecision(id: String, answer: String, answeredBy: String) async throws -> Decision {
        try await send(.answerDecision(id: id, answer: answer, answeredBy: answeredBy))
    }

    // MARK: - Session Transcripts

    public func createSessionTranscript(_ input: SessionTranscriptInput) async throws -> SessionTranscript {
        try await send(.createTranscript(payload: input.toDictionary()))
    }

    public func getSessionTranscripts(companySlug: String? = nil, taskId: String? = nil, limit: Int = 20) async throws -> [SessionTranscript] {
        try await send(.listTranscripts(companySlug: companySlug, taskId: taskId, limit: limit))
    }

    public func getSessionTranscript(id: String) async throws -> SessionTranscript {
        try await send(.getTranscript(id: id))
    }

    // MARK: - Board

    public func getBoardOverview() async throws -> [BoardEntry] {
        try await send(.boardOverview)
    }

    // MARK: - Health

    public func healthCheck() async throws -> Bool {
        let endpoint = ConfigurableEndpoint(
            base: .health,
            host: endpointHost,
            port: endpointPort,
            scheme: endpointScheme
        )
        let request = network.createRequest(endPoint: endpoint)
        do {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 5
            let session = URLSession(configuration: config)
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<400).contains(http.statusCode)
        } catch {
            return false
        }
    }

    // MARK: - Internal

    /// Send a typed endpoint request and decode the response via `NetworkProtocol.sendRequest`.
    ///
    /// All backend models use `String` for date fields with explicit `CodingKeys`,
    /// so NetKit's default decoder (which includes PocketBase date strategy) works fine —
    /// the custom date decoder only activates on `Date` typed properties, which these models don't have.
    private func send<T: Decodable & Sendable>(_ endpoint: ShikiBackendEndpoint) async throws -> T {
        let configured = ConfigurableEndpoint(
            base: endpoint,
            host: endpointHost,
            port: endpointPort,
            scheme: endpointScheme
        )
        do {
            return try await network.sendRequest(endpoint: configured)
        } catch let error as NetworkError {
            let mapped = mapNetworkError(error, path: endpoint.path, method: endpoint.method.rawValue)
            throw mapped
        } catch {
            logger.error("\(endpoint.method.rawValue) \(endpoint.path) request failed: \(error)")
            throw BackendError.httpError(statusCode: 0, body: error.localizedDescription)
        }
    }

    /// Convert NetKit errors to BackendError for backward compatibility with callers.
    private func mapNetworkError(_ error: NetworkError, path: String, method: String) -> BackendError {
        switch error {
        case .unexpectedStatusCode(let code, _):
            logger.error("\(method) \(path) HTTP \(code)")
            return .httpError(statusCode: code, body: error.description)
        case .requestFailed(let description):
            logger.error("\(method) \(path) failed: \(description)")
            return .httpError(statusCode: 0, body: description)
        case .jsonParsingFailed(let decoding):
            logger.error("\(method) \(path) decode error: \(decoding)")
            return .httpError(statusCode: 200, body: "JSON decode error: \(decoding)")
        case .invalidData:
            return .httpError(statusCode: 0, body: "Invalid data")
        default:
            return .httpError(statusCode: 0, body: error.description)
        }
    }
}

// MARK: - ConfigurableEndpoint

/// Wraps a `ShikiBackendEndpoint` to override host/port/scheme from BackendClient's baseURL.
struct ConfigurableEndpoint: EndPoint, @unchecked Sendable {
    let base: ShikiBackendEndpoint
    let host: String
    let port: Int?
    let scheme: String

    var apiPath: String { base.apiPath }
    var apiFilePath: String { base.apiFilePath }
    var path: String { base.path }
    var method: RequestMethod { base.method }
    var header: [String: String]? { base.header }
    var body: [String: Any]? { base.body }
    var queryParams: [String: Any]? { base.queryParams }
}

// MARK: - SessionTranscriptInput

public struct SessionTranscriptInput: Sendable {
    public let companyId: String
    public let sessionId: String
    public let companySlug: String
    public let taskTitle: String
    public let phase: String
    public let taskId: String?
    public let projectPath: String?
    public let summary: String?
    public let planOutput: String?
    public let filesChanged: [String]?
    public let testResults: String?
    public let prsCreated: [String]?
    public let errors: [String]?
    public let durationMinutes: Int?
    public let contextPct: Int?
    public let compactionCount: Int?
    public let rawLog: String?

    public init(
        companyId: String,
        sessionId: String,
        companySlug: String,
        taskTitle: String,
        phase: String,
        taskId: String? = nil,
        projectPath: String? = nil,
        summary: String? = nil,
        planOutput: String? = nil,
        filesChanged: [String]? = nil,
        testResults: String? = nil,
        prsCreated: [String]? = nil,
        errors: [String]? = nil,
        durationMinutes: Int? = nil,
        contextPct: Int? = nil,
        compactionCount: Int? = nil,
        rawLog: String? = nil
    ) {
        self.companyId = companyId
        self.sessionId = sessionId
        self.companySlug = companySlug
        self.taskTitle = taskTitle
        self.phase = phase
        self.taskId = taskId
        self.projectPath = projectPath
        self.summary = summary
        self.planOutput = planOutput
        self.filesChanged = filesChanged
        self.testResults = testResults
        self.prsCreated = prsCreated
        self.errors = errors
        self.durationMinutes = durationMinutes
        self.contextPct = contextPct
        self.compactionCount = compactionCount
        self.rawLog = rawLog
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "companyId": companyId,
            "sessionId": sessionId,
            "companySlug": companySlug,
            "taskTitle": taskTitle,
            "phase": phase,
        ]
        if let taskId { dict["taskId"] = taskId }
        if let projectPath { dict["projectPath"] = projectPath }
        if let summary { dict["summary"] = summary }
        if let planOutput { dict["planOutput"] = planOutput }
        if let filesChanged { dict["filesChanged"] = filesChanged }
        if let testResults { dict["testResults"] = testResults }
        if let prsCreated { dict["prsCreated"] = prsCreated }
        if let errors { dict["errors"] = errors }
        if let durationMinutes { dict["durationMinutes"] = durationMinutes }
        if let contextPct { dict["contextPct"] = contextPct }
        if let compactionCount { dict["compactionCount"] = compactionCount }
        if let rawLog { dict["rawLog"] = rawLog }
        return dict
    }
}

public enum BackendError: Error, CustomStringConvertible {
    case httpError(statusCode: Int, body: String)

    public var description: String {
        switch self {
        case .httpError(let code, let body):
            "HTTP \(code): \(body)"
        }
    }
}
