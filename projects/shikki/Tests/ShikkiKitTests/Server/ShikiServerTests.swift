import Foundation
import Testing

@testable import ShikkiKit

@Suite("ShikiServer")
struct ShikiServerTests {
    // MARK: - Helpers

    /// Start a server on an ephemeral port and return (server, port).
    private func startServer() async throws -> (ShikiServer, Int) {
        let server = ShikiServer(port: 0) // 0 = OS picks a free port
        try await server.start()
        let port = server.actualPort
        return (server, port)
    }

    private func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, response as! HTTPURLResponse)
    }

    private func post(_ url: URL, body: [String: Any]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, response as! HTTPURLResponse)
    }

    private func patch(_ url: URL, body: [String: Any]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, response as! HTTPURLResponse)
    }

    // MARK: - 1. Health check returns 200 with {"ok": true}

    @Test("Health check returns 200 with ok true")
    func healthCheck() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }

        let url = URL(string: "http://127.0.0.1:\(port)/health")!
        let (data, response) = try await get(url)

        #expect(response.statusCode == 200)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["ok"] as? Bool == true)
    }

    // MARK: - 2. POST /api/data-sync stores event and returns ok

    @Test("POST data-sync stores event and returns ok")
    func dataSyncStoresEvent() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }

        let url = URL(string: "http://127.0.0.1:\(port)/api/data-sync")!
        let body: [String: Any] = [
            "type": "agent_event",
            "projectId": "test-project",
            "payload": ["key": "value"],
        ]
        let (data, response) = try await post(url, body: body)

        #expect(response.statusCode == 200)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["ok"] as? Bool == true)

        // Verify it was stored in events (agent_event goes to events collection)
        let eventsURL = URL(string: "http://127.0.0.1:\(port)/api/events")!
        let (eventsData, eventsResponse) = try await get(eventsURL)
        #expect(eventsResponse.statusCode == 200)
        let events = try JSONSerialization.jsonObject(with: eventsData) as! [[String: Any]]
        #expect(events.count == 1)
        #expect(events[0]["type"] as? String == "agent_event")
    }

    // MARK: - 3. POST /api/memories/search returns matching results

    @Test("POST memories/search returns matching results")
    func memoriesSearchReturnsMatches() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }

        // Seed some memories via data-sync
        let syncURL = URL(string: "http://127.0.0.1:\(port)/api/data-sync")!
        let (_, seedResp1) = try await post(syncURL, body: [
            "type": "memory",
            "projectId": "proj-1",
            "payload": ["content": "Swift concurrency is powerful", "tags": ["swift", "concurrency"]],
        ])
        #expect(seedResp1.statusCode == 200)

        let (_, seedResp2) = try await post(syncURL, body: [
            "type": "memory",
            "projectId": "proj-1",
            "payload": ["content": "Rust memory safety", "tags": ["rust", "safety"]],
        ])
        #expect(seedResp2.statusCode == 200)

        // Search
        let searchURL = URL(string: "http://127.0.0.1:\(port)/api/memories/search")!
        let (data, response) = try await post(searchURL, body: [
            "query": "swift",
            "projectIds": ["proj-1"],
        ])

        #expect(response.statusCode == 200)
        let results = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        #expect(results.count >= 1)
        // The Swift result should match -- payload is extracted from data-sync
        let contents = results.compactMap { $0["content"] as? String }
        #expect(contents.contains("Swift concurrency is powerful"))
    }

    // MARK: - 4. GET /api/events returns stored events

    @Test("GET events returns stored events")
    func getEventsReturnsStored() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }

        // Store two events
        let syncURL = URL(string: "http://127.0.0.1:\(port)/api/data-sync")!
        _ = try await post(syncURL, body: [
            "type": "session_start",
            "projectId": "proj-a",
            "payload": ["session": "s1"],
        ])
        _ = try await post(syncURL, body: [
            "type": "session_end",
            "projectId": "proj-a",
            "payload": ["session": "s1"],
        ])

        let eventsURL = URL(string: "http://127.0.0.1:\(port)/api/events")!
        let (data, response) = try await get(eventsURL)

        #expect(response.statusCode == 200)
        let events = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        #expect(events.count == 2)
    }

    // MARK: - 5. GET /api/decisions returns stored decisions

    @Test("GET decisions returns stored decisions")
    func getDecisionsReturnsStored() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }

        // Store a decision via data-sync
        let syncURL = URL(string: "http://127.0.0.1:\(port)/api/data-sync")!
        _ = try await post(syncURL, body: [
            "type": "decision",
            "projectId": "proj-b",
            "payload": [
                "question": "Use Swift or Rust?",
                "answer": "Swift",
                "context": "CLI tool",
            ] as [String: Any],
        ])

        let decisionsURL = URL(string: "http://127.0.0.1:\(port)/api/decisions")!
        let (data, response) = try await get(decisionsURL)

        #expect(response.statusCode == 200)
        let decisions = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        #expect(decisions.count == 1)
        #expect(decisions[0]["question"] as? String == "Use Swift or Rust?")
    }

    // MARK: - 6. Server starts on configurable port

    @Test("Server starts on configurable port")
    func configurablePort() async throws {
        let server = ShikiServer(port: 0)
        try await server.start()
        defer { server.stop() }

        let port = server.actualPort
        #expect(port > 0)
        #expect(port != 0)

        // Verify it responds
        let url = URL(string: "http://127.0.0.1:\(port)/health")!
        let (_, response) = try await get(url)
        #expect(response.statusCode == 200)
    }

    // MARK: - 7. Server handles concurrent requests

    @Test("Server handles concurrent requests")
    func concurrentRequests() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }

        // Fire 10 concurrent health checks
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let url = URL(string: "http://127.0.0.1:\(port)/health")!
                    let (_, response) = try await self.get(url)
                    return response.statusCode
                }
            }
            var successCount = 0
            for try await statusCode in group {
                if statusCode == 200 { successCount += 1 }
            }
            #expect(successCount == 10)
        }
    }

    // MARK: - 8. Invalid JSON returns 400

    @Test("Invalid JSON returns 400")
    func invalidJSONReturns400() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }

        let url = URL(string: "http://127.0.0.1:\(port)/api/data-sync")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("not valid json{{{".utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        #expect(response is HTTPURLResponse)
        let httpResponse = response as! HTTPURLResponse
        #expect(httpResponse.statusCode == 400)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["error"] as? String != nil)
    }

    // MARK: - 9. POST /api/plans stores and GET retrieves

    @Test("Plans CRUD via data-sync and GET")
    func plansCRUD() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }

        let syncURL = URL(string: "http://127.0.0.1:\(port)/api/data-sync")!
        _ = try await post(syncURL, body: [
            "type": "plan",
            "projectId": "proj-c",
            "payload": [
                "title": "Migration plan",
                "waves": 3,
            ] as [String: Any],
        ])

        let plansURL = URL(string: "http://127.0.0.1:\(port)/api/plans")!
        let (data, response) = try await get(plansURL)

        #expect(response.statusCode == 200)
        let plans = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        #expect(plans.count == 1)
        #expect(plans[0]["title"] as? String == "Migration plan")
    }

    // MARK: - 10. Unknown route returns 404

    @Test("Unknown route returns 404")
    func unknownRouteReturns404() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }

        let url = URL(string: "http://127.0.0.1:\(port)/api/nonexistent")!
        let (data, response) = try await get(url)

        #expect(response.statusCode == 404)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["error"] as? String != nil)
    }
}
