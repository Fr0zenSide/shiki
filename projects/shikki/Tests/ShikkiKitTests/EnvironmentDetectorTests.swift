import Testing
@testable import ShikkiKit

@Suite("EnvironmentDetector")
struct EnvironmentDetectorTests {

    @Test("MockEnvironmentChecker returns configured values")
    func mockReturnsConfiguredValues() async {
        let mock = MockEnvironmentChecker()
        mock.dockerRunning = true
        mock.colimaRunning = false
        mock.backendHealthy = true
        mock.lmStudioRunning = false
        mock.tmuxSessionRunning = true
        mock.binaryExistsResult = true
        mock.companyCountResult = 6

        #expect(await mock.isDockerRunning() == true)
        #expect(await mock.isColimaRunning() == false)
        #expect(await mock.isBackendHealthy(url: "http://localhost:3900") == true)
        #expect(await mock.isLMStudioRunning(url: "http://127.0.0.1:1234") == false)
        #expect(await mock.isTmuxSessionRunning(name: "shiki-board") == true)
        #expect(mock.binaryExists(at: "/usr/bin/env") == true)
        #expect(await mock.companyCount(backendURL: "http://localhost:3900") == 6)
    }

    @Test("MockEnvironmentChecker defaults to all false/zero")
    func mockDefaultsToFalse() async {
        let mock = MockEnvironmentChecker()

        #expect(await mock.isDockerRunning() == false)
        #expect(await mock.isColimaRunning() == false)
        #expect(await mock.isBackendHealthy(url: "http://localhost:3900") == false)
        #expect(await mock.isLMStudioRunning(url: "http://127.0.0.1:1234") == false)
        #expect(await mock.isTmuxSessionRunning(name: "shiki-board") == false)
        #expect(mock.binaryExists(at: "/nonexistent/path") == false)
        #expect(await mock.companyCount(backendURL: "http://localhost:3900") == 0)
    }

    @Test("Real detector: binaryExists returns true for /usr/bin/env")
    func realBinaryExists() {
        let detector = EnvironmentDetector()
        #expect(detector.binaryExists(at: "/usr/bin/env") == true)
    }

    @Test("Real detector: binaryExists returns false for nonexistent path")
    func realBinaryNotExists() {
        let detector = EnvironmentDetector()
        #expect(detector.binaryExists(at: "/nonexistent/binary/path") == false)
    }
}
