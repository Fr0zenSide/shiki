import Foundation
import Testing
@testable import ShikkiKit

// MARK: - Mock Health Check

/// Mock implementation of NATSHealthCheckProtocol for unit tests.
/// Returns pre-configured results without touching the network.
final class MockNATSHealthCheck: NATSHealthCheckProtocol, @unchecked Sendable {
    var results: [NATSHealthResult] = []
    var pingCallCount = 0
    private var index = 0

    init(results: [NATSHealthResult] = [.healthy(latencyMs: 1.0)]) {
        self.results = results
    }

    func ping() async -> NATSHealthResult {
        pingCallCount += 1
        guard !results.isEmpty else {
            return .unhealthy("no results configured")
        }
        let result = results[min(index, results.count - 1)]
        index += 1
        return result
    }
}

// MARK: - Tests

@Suite("NATSHealthCheck — Health result model")
struct NATSHealthResultTests {

    @Test("Healthy result has correct properties")
    func healthyResult() {
        let result = NATSHealthResult.healthy(latencyMs: 2.5)
        #expect(result.isHealthy)
        #expect(result.latencyMs == 2.5)
        #expect(result.message.contains("2.5ms"))
    }

    @Test("Unhealthy result has nil latency")
    func unhealthyResult() {
        let result = NATSHealthResult.unhealthy("connection refused")
        #expect(!result.isHealthy)
        #expect(result.latencyMs == nil)
        #expect(result.message.contains("connection refused"))
    }

    @Test("Healthy result message format")
    func healthyMessageFormat() {
        let result = NATSHealthResult.healthy(latencyMs: 0.8)
        #expect(result.message == "NATS OK (0.8ms)")
    }

    @Test("Unhealthy result message format")
    func unhealthyMessageFormat() {
        let result = NATSHealthResult.unhealthy("timeout")
        #expect(result.message == "NATS unhealthy: timeout")
    }

    @Test("Custom init preserves all fields")
    func customInit() {
        let result = NATSHealthResult(
            isHealthy: true,
            latencyMs: 42.0,
            message: "custom message"
        )
        #expect(result.isHealthy)
        #expect(result.latencyMs == 42.0)
        #expect(result.message == "custom message")
    }

    @Test("Equatable conformance works")
    func equatable() {
        let a = NATSHealthResult(isHealthy: true, latencyMs: 1.0, message: "ok")
        let b = NATSHealthResult(isHealthy: true, latencyMs: 1.0, message: "ok")
        let c = NATSHealthResult(isHealthy: false, latencyMs: nil, message: "fail")
        #expect(a == b)
        #expect(a != c)
    }
}

@Suite("NATSHealthCheck — Mock behavior")
struct MockNATSHealthCheckTests {

    @Test("Mock returns configured result")
    func mockReturnsResult() async {
        let mock = MockNATSHealthCheck(results: [.healthy(latencyMs: 5.0)])
        let result = await mock.ping()
        #expect(result.isHealthy)
        #expect(result.latencyMs == 5.0)
        #expect(mock.pingCallCount == 1)
    }

    @Test("Mock cycles through results")
    func mockCyclesResults() async {
        let mock = MockNATSHealthCheck(results: [
            .unhealthy("first call"),
            .unhealthy("second call"),
            .healthy(latencyMs: 1.0),
        ])

        let r1 = await mock.ping()
        #expect(!r1.isHealthy)

        let r2 = await mock.ping()
        #expect(!r2.isHealthy)

        let r3 = await mock.ping()
        #expect(r3.isHealthy)

        #expect(mock.pingCallCount == 3)
    }

    @Test("Mock with empty results returns unhealthy")
    func mockEmptyResults() async {
        let mock = MockNATSHealthCheck(results: [])
        let result = await mock.ping()
        #expect(!result.isHealthy)
    }
}
