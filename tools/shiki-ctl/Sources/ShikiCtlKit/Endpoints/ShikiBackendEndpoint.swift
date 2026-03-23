import Foundation
import NetKit

/// Typed endpoints for the Shiki orchestrator backend API.
///
/// Each case maps to one backend route with its HTTP method, path,
/// query parameters, and request body. Used with `NetworkProtocol.createRequest(endPoint:)`
/// to build `URLRequest` values without manual string concatenation.
enum ShikiBackendEndpoint: EndPoint, @unchecked Sendable {
    // Orchestrator
    case health
    case orchestratorStatus
    case staleCompanies(thresholdMinutes: Int)
    case readyCompanies
    case dispatcherQueue
    case dailyReport(date: String?)
    case heartbeat(companyId: String, sessionId: String)

    // Companies
    case companies(status: String?)
    case patchCompany(id: String, updates: [String: Any])

    // Decisions
    case pendingDecisions
    case answerDecision(id: String, answer: String, answeredBy: String)

    // Session Transcripts
    case createTranscript(payload: [String: Any])
    case listTranscripts(companySlug: String?, taskId: String?, limit: Int)
    case getTranscript(id: String)

    // Board
    case boardOverview

    // MARK: - EndPoint

    var host: String { "localhost" }
    var port: Int? { 3900 }
    var scheme: String { "http" }
    var apiPath: String { "" }
    var apiFilePath: String { "" }

    var path: String {
        switch self {
        case .health:
            "/health"
        case .orchestratorStatus:
            "/api/orchestrator/status"
        case .staleCompanies:
            "/api/orchestrator/stale"
        case .readyCompanies:
            "/api/orchestrator/ready"
        case .dispatcherQueue:
            "/api/orchestrator/dispatcher-queue"
        case .dailyReport:
            "/api/orchestrator/report"
        case .heartbeat:
            "/api/orchestrator/heartbeat"
        case .companies:
            "/api/companies"
        case .patchCompany(let id, _):
            "/api/companies/\(id)"
        case .pendingDecisions:
            "/api/decision-queue/pending"
        case .answerDecision(let id, _, _):
            "/api/decision-queue/\(id)"
        case .createTranscript:
            "/api/session-transcripts"
        case .listTranscripts:
            "/api/session-transcripts"
        case .getTranscript(let id):
            "/api/session-transcripts/\(id)"
        case .boardOverview:
            "/api/orchestrator/board"
        }
    }

    var method: RequestMethod {
        switch self {
        case .health, .orchestratorStatus, .staleCompanies, .readyCompanies,
             .dispatcherQueue, .dailyReport, .companies, .pendingDecisions,
             .listTranscripts, .getTranscript, .boardOverview:
            .GET
        case .heartbeat, .createTranscript:
            .POST
        case .patchCompany, .answerDecision:
            .PATCH
        }
    }

    var header: [String: String]? {
        switch self {
        case .health:
            ["Accept": "application/json"]
        default:
            [
                "Accept": "application/json",
                "Content-Type": "application/json",
            ]
        }
    }

    var body: [String: Any]? {
        switch self {
        case .heartbeat(let companyId, let sessionId):
            ["companyId": companyId, "sessionId": sessionId]
        case .patchCompany(_, let updates):
            updates
        case .answerDecision(_, let answer, let answeredBy):
            ["answer": answer, "answeredBy": answeredBy]
        case .createTranscript(let payload):
            payload
        default:
            nil
        }
    }

    var queryParams: [String: Any]? {
        switch self {
        case .staleCompanies(let thresholdMinutes):
            return ["threshold_minutes": String(thresholdMinutes)]
        case .dailyReport(let date):
            return date.map { ["date": $0] }
        case .companies(let status):
            return status.map { ["status": $0] }
        case .listTranscripts(let companySlug, let taskId, let limit):
            var params: [String: String] = ["limit": String(limit)]
            if let slug = companySlug { params["company_slug"] = slug }
            if let tid = taskId { params["task_id"] = tid }
            return params
        default:
            return nil
        }
    }
}
