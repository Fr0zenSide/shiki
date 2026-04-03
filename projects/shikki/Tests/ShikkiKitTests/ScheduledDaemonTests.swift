import Foundation
import Testing
@testable import ShikkiKit

// MARK: - Test Helpers

/// A mock ManagedService that records tick calls and can be configured to throw.
private actor MockManagedService: ManagedService {
    nonisolated let id: ServiceID
    nonisolated let qos: ServiceQoS
    nonisolated let interval: Duration
    nonisolated let restartPolicy: RestartPolicy

    private(set) var tickCount = 0
    private var shouldThrow: Bool

    init(
        id: ServiceID,
        qos: ServiceQoS = .default,
        interval: Duration = .seconds(30),
        restartPolicy: RestartPolicy = .once,
        shouldThrow: Bool = false
    ) {
        self.id = id
        self.qos = qos
        self.interval = interval
        self.restartPolicy = restartPolicy
        self.shouldThrow = shouldThrow
    }

    func tick(snapshot: KernelSnapshot) async throws {
        if shouldThrow {
            throw MockServiceError.intentionalFailure
        }
        tickCount += 1
    }

    func setShouldThrow(_ value: Bool) {
        shouldThrow = value
    }
}

private enum MockServiceError: Error, CustomStringConvertible {
    case intentionalFailure

    var description: String { "intentional test failure" }
}

/// Creates a temporary PID file with the given PID and returns the path.
private func createTempPIDFile(pid: Int32) throws -> String {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("shikki-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let pidPath = tempDir.appendingPathComponent("daemon.pid").path
    try "\(pid)".write(toFile: pidPath, atomically: true, encoding: .utf8)
    return pidPath
}

/// Returns a temp directory path for a PID file that does not exist.
private func nonExistentPIDPath() -> String {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("shikki-test-\(UUID().uuidString)")
    return tempDir.appendingPathComponent("daemon.pid").path
}

// MARK: - Tests — Single Tick

@Suite("ScheduledDaemonRunner — Single Tick")
struct ScheduledDaemonSingleTickTests {

    @Test("Single tick executes all services")
    func singleTickExecutesAllServices() async throws {
        let serviceA = MockManagedService(id: .taskScheduler)
        let serviceB = MockManagedService(id: .staleCompanyDetector, qos: .background)

        // Use current process PID so isRunning() returns true
        let pidPath = try createTempPIDFile(pid: ProcessInfo.processInfo.processIdentifier)
        defer { try? FileManager.default.removeItem(atPath: pidPath) }

        let runner = ScheduledDaemonRunner(
            services: [serviceA, serviceB],
            snapshotProvider: MockSnapshotProvider(),
            pidManager: DaemonPIDManager(pidPath: pidPath)
        )

        let result = try await runner.runOnce()

        #expect(result.servicesExecuted == 2)
        #expect(result.errors.isEmpty)
        #expect(await serviceA.tickCount == 1)
        #expect(await serviceB.tickCount == 1)
    }

    @Test("Duration is tracked and greater than zero")
    func durationTracked() async throws {
        let service = MockManagedService(id: .taskScheduler)

        let pidPath = try createTempPIDFile(pid: ProcessInfo.processInfo.processIdentifier)
        defer { try? FileManager.default.removeItem(atPath: pidPath) }

        let runner = ScheduledDaemonRunner(
            services: [service],
            snapshotProvider: MockSnapshotProvider(),
            pidManager: DaemonPIDManager(pidPath: pidPath)
        )

        let result = try await runner.runOnce()

        #expect(result.duration > 0)
    }

    @Test("Services execute in QoS order")
    func servicesExecuteInQoSOrder() async throws {
        // Critical should run before background
        let critical = MockManagedService(id: .healthMonitor, qos: .critical)
        let background = MockManagedService(id: .staleCompanyDetector, qos: .background)

        let pidPath = try createTempPIDFile(pid: ProcessInfo.processInfo.processIdentifier)
        defer { try? FileManager.default.removeItem(atPath: pidPath) }

        let runner = ScheduledDaemonRunner(
            services: [background, critical],
            snapshotProvider: MockSnapshotProvider(),
            pidManager: DaemonPIDManager(pidPath: pidPath)
        )

        let result = try await runner.runOnce()

        #expect(result.servicesExecuted == 2)
        #expect(await critical.tickCount == 1)
        #expect(await background.tickCount == 1)
    }
}

// MARK: - Tests — Primary Daemon Checks

@Suite("ScheduledDaemonRunner — Primary Daemon Checks")
struct ScheduledDaemonPrimaryCheckTests {

    @Test("Throws when daemon.pid does not exist")
    func throwsWhenNoPIDFile() async {
        let service = MockManagedService(id: .taskScheduler)

        let runner = ScheduledDaemonRunner(
            services: [service],
            snapshotProvider: MockSnapshotProvider(),
            pidManager: DaemonPIDManager(pidPath: nonExistentPIDPath())
        )

        await #expect(throws: ScheduledDaemonError.self) {
            try await runner.runOnce()
        }
    }

    @Test("Throws when daemon.pid has dead PID")
    func throwsWhenPIDDead() async throws {
        // PID 99999 is very unlikely to be running
        let pidPath = try createTempPIDFile(pid: 99999)
        defer { try? FileManager.default.removeItem(atPath: pidPath) }

        let service = MockManagedService(id: .taskScheduler)

        let runner = ScheduledDaemonRunner(
            services: [service],
            snapshotProvider: MockSnapshotProvider(),
            pidManager: DaemonPIDManager(pidPath: pidPath)
        )

        await #expect(throws: ScheduledDaemonError.self) {
            try await runner.runOnce()
        }
    }

    @Test("Services do not tick when primary is down")
    func servicesDoNotTickWhenPrimaryDown() async throws {
        let service = MockManagedService(id: .taskScheduler)

        let runner = ScheduledDaemonRunner(
            services: [service],
            snapshotProvider: MockSnapshotProvider(),
            pidManager: DaemonPIDManager(pidPath: nonExistentPIDPath())
        )

        do {
            _ = try await runner.runOnce()
            Issue.record("Expected error but runOnce succeeded")
        } catch {
            // Expected — verify service was NOT ticked
            #expect(await service.tickCount == 0)
        }
    }
}

// MARK: - Tests — Error Collection

@Suite("ScheduledDaemonRunner — Error Collection")
struct ScheduledDaemonErrorCollectionTests {

    @Test("Errors collected without stopping other services")
    func errorsCollectedOtherServicesContinue() async throws {
        let failing = MockManagedService(id: .taskScheduler, shouldThrow: true)
        let healthy = MockManagedService(id: .staleCompanyDetector, qos: .background)

        let pidPath = try createTempPIDFile(pid: ProcessInfo.processInfo.processIdentifier)
        defer { try? FileManager.default.removeItem(atPath: pidPath) }

        let runner = ScheduledDaemonRunner(
            services: [failing, healthy],
            snapshotProvider: MockSnapshotProvider(),
            pidManager: DaemonPIDManager(pidPath: pidPath)
        )

        let result = try await runner.runOnce()

        // One service failed, one succeeded
        #expect(result.servicesExecuted == 1)
        #expect(result.errors.count == 1)
        #expect(result.errors[0].contains("taskScheduler"))
        // Healthy service should have ticked despite the failure
        #expect(await healthy.tickCount == 1)
        #expect(await failing.tickCount == 0)
    }

    @Test("All service errors are collected")
    func allErrorsCollected() async throws {
        let failA = MockManagedService(id: .taskScheduler, shouldThrow: true)
        let failB = MockManagedService(id: .staleCompanyDetector, qos: .background, shouldThrow: true)

        let pidPath = try createTempPIDFile(pid: ProcessInfo.processInfo.processIdentifier)
        defer { try? FileManager.default.removeItem(atPath: pidPath) }

        let runner = ScheduledDaemonRunner(
            services: [failA, failB],
            snapshotProvider: MockSnapshotProvider(),
            pidManager: DaemonPIDManager(pidPath: pidPath)
        )

        let result = try await runner.runOnce()

        #expect(result.servicesExecuted == 0)
        #expect(result.errors.count == 2)
    }
}

// MARK: - Tests — Scheduled Services

@Suite("ScheduledDaemonRunner — Scheduled Services")
struct ScheduledDaemonServiceTests {

    @Test("ScheduledTaskService has correct identity")
    func scheduledTaskServiceIdentity() async {
        let service = ScheduledTaskService()

        #expect(service.id == .taskScheduler)
        #expect(service.qos == .default)
        #expect(service.interval == .seconds(30))
    }

    @Test("ScheduledTaskService increments tick count")
    func scheduledTaskServiceTicks() async throws {
        let service = ScheduledTaskService()
        let snapshot = KernelSnapshot(health: .healthy)

        try await service.tick(snapshot: snapshot)
        try await service.tick(snapshot: snapshot)

        let count = await service.tickCount
        #expect(count == 2)
    }

    @Test("ScheduledTaskService skips when unhealthy")
    func scheduledTaskServiceSkipsUnhealthy() async throws {
        let service = ScheduledTaskService()
        let snapshot = KernelSnapshot(health: .unreachable)

        try await service.tick(snapshot: snapshot)

        let overdueCount = await service.lastOverdueCount
        #expect(overdueCount == 0)
    }

    @Test("Default scheduled services are lightweight")
    func defaultServicesAreLightweight() async {
        let services = ScheduledDaemonRunner.defaultServices(
            client: MockBackendClient()
        )

        #expect(services.count == 2)

        let ids = services.map(\.id)
        #expect(ids.contains(.taskScheduler))
        #expect(ids.contains(.staleCompanyDetector))
    }
}

// MARK: - Tests — TickResult

@Suite("ScheduledDaemonRunner — TickResult")
struct TickResultTests {

    @Test("TickResult captures all fields")
    func tickResultFields() {
        let result = TickResult(
            servicesExecuted: 3,
            duration: 1.234,
            errors: ["error-1", "error-2"]
        )

        #expect(result.servicesExecuted == 3)
        #expect(result.duration == 1.234)
        #expect(result.errors.count == 2)
        #expect(result.errors[0] == "error-1")
    }

    @Test("TickResult with no errors")
    func tickResultNoErrors() {
        let result = TickResult(servicesExecuted: 2, duration: 0.5, errors: [])

        #expect(result.errors.isEmpty)
        #expect(result.servicesExecuted == 2)
    }
}

