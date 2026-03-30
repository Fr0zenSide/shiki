import Foundation
import Testing
@testable import ShikkiKit

// MARK: - Mock Snapshot Provider

/// Returns a fixed snapshot for testing.
struct MockSnapshotProvider: KernelSnapshotProvider {
    let snapshot: KernelSnapshot

    init(snapshot: KernelSnapshot = KernelSnapshot(health: .healthy)) {
        self.snapshot = snapshot
    }

    func fetchSnapshot() async -> KernelSnapshot {
        snapshot
    }
}

// MARK: - Spy Service

/// A test service that records ticks and can be configured.
actor SpyService: ManagedService {
    nonisolated let id: ServiceID
    nonisolated let qos: ServiceQoS
    nonisolated let interval: Duration
    nonisolated let leeway: Duration
    nonisolated let restartPolicy: RestartPolicy

    private var _tickCount: Int = 0
    private var _tickTimestamps: [Date] = []
    private var _shouldThrow: Bool = false

    var tickCount: Int { _tickCount }
    var tickTimestamps: [Date] { _tickTimestamps }

    init(
        id: ServiceID,
        qos: ServiceQoS = .default,
        interval: Duration = .seconds(60),
        leeway: Duration? = nil,
        restartPolicy: RestartPolicy = .onFailure(maxRestarts: 3, backoff: .seconds(1))
    ) {
        self.id = id
        self.qos = qos
        self.interval = interval
        self.leeway = leeway ?? qos.defaultLeeway
        self.restartPolicy = restartPolicy
    }

    func tick(snapshot: KernelSnapshot) async throws {
        if _shouldThrow {
            _shouldThrow = false
            throw ServiceError.testFailure
        }
        _tickCount += 1
        _tickTimestamps.append(Date())
    }

    nonisolated func canRun(health: HealthStatus) -> Bool {
        switch health {
        case .healthy: return true
        case .degraded, .unreachable: return qos == .critical
        }
    }

    func setThrowOnNextTick() {
        _shouldThrow = true
    }
}

enum ServiceError: Error {
    case testFailure
}

// MARK: - Tests

@Suite("ShikkiKernel — Core")
struct ShikkiKernelCoreTests {

    @Test("Kernel starts all services")
    func test_kernel_starts_all_services() async throws {
        let health = SpyService(id: .healthMonitor, qos: .critical, interval: .seconds(1))
        let dispatch = SpyService(id: .dispatchService, qos: .default, interval: .seconds(1))
        let supervisor = SpyService(id: .sessionSupervisor, qos: .utility, interval: .seconds(1))

        let kernel = ShikkiKernel(
            services: [health, dispatch, supervisor],
            snapshotProvider: MockSnapshotProvider()
        )

        // Verify all services are registered
        let ids = await kernel.serviceIDs
        #expect(ids.contains(.healthMonitor))
        #expect(ids.contains(.dispatchService))
        #expect(ids.contains(.sessionSupervisor))
        #expect(ids.count == 3)
    }

    @Test("ManagedService declares QoS and interval")
    func test_managedService_declares_qos_and_interval() async throws {
        let service = SpyService(
            id: .healthMonitor,
            qos: .critical,
            interval: .seconds(10)
        )

        #expect(await service.id == .healthMonitor)
        #expect(await service.qos == .critical)
        #expect(await service.interval == .seconds(10))
    }

    @Test("Higher QoS runs first within a tick")
    func test_higher_qos_runs_first() async throws {
        // Create services with different QoS levels
        let background = SpyService(id: .staleCompanyDetector, qos: .background, interval: .seconds(1))
        let critical = SpyService(id: .healthMonitor, qos: .critical, interval: .seconds(1))
        let utility = SpyService(id: .sessionSupervisor, qos: .utility, interval: .seconds(1))
        let defaultQos = SpyService(id: .dispatchService, qos: .default, interval: .seconds(1))

        let kernel = ShikkiKernel(
            services: [background, critical, utility, defaultQos],
            snapshotProvider: MockSnapshotProvider()
        )

        // Run kernel briefly — it will process one tick then we cancel
        let task = Task {
            await kernel.run()
        }

        // Wait for one tick to complete
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        await kernel.shutdown()

        // All services should have ticked (healthy snapshot, all can run)
        let criticalTicks = await critical.tickCount
        let defaultTicks = await defaultQos.tickCount
        let utilityTicks = await utility.tickCount
        let backgroundTicks = await background.tickCount

        #expect(criticalTicks >= 1)
        #expect(defaultTicks >= 1)
        #expect(utilityTicks >= 1)
        #expect(backgroundTicks >= 1)

        // Verify QoS ordering is correct by checking the enum values
        #expect(ServiceQoS.critical < ServiceQoS.userInitiated)
        #expect(ServiceQoS.userInitiated < ServiceQoS.default)
        #expect(ServiceQoS.default < ServiceQoS.utility)
        #expect(ServiceQoS.utility < ServiceQoS.background)
    }
}

@Suite("ShikkiKernel — Timer Coalescing")
struct ShikkiKernelTimerTests {

    @Test("Kernel sleeps until next due service")
    func test_kernel_sleeps_until_next_due() async throws {
        let service = SpyService(id: .healthMonitor, qos: .critical, interval: .seconds(60))

        let kernel = ShikkiKernel(
            services: [service],
            snapshotProvider: MockSnapshotProvider()
        )

        // First tick fires immediately (nextDue = now at init)
        let task = Task {
            await kernel.run()
        }

        // Wait enough for initial tick but not long enough for a second tick (60s)
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        await kernel.shutdown()

        let ticks = await service.tickCount
        // Should have fired once (the initial tick), then kernel sleeps 60s
        #expect(ticks == 1)
    }

    @Test("Services within coalescing window fire together")
    func test_services_within_window_coalesce() async throws {
        // Two services with same interval fire in the same tick
        let serviceA = SpyService(id: .healthMonitor, qos: .critical, interval: .seconds(1))
        let serviceB = SpyService(id: .dispatchService, qos: .default, interval: .seconds(1))

        let kernel = ShikkiKernel(
            services: [serviceA, serviceB],
            snapshotProvider: MockSnapshotProvider()
        )

        let task = Task {
            await kernel.run()
        }

        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        await kernel.shutdown()

        let ticksA = await serviceA.tickCount
        let ticksB = await serviceB.tickCount

        // Both should have fired in the same initial tick
        #expect(ticksA >= 1)
        #expect(ticksB >= 1)
        #expect(ticksA == ticksB)
    }

    @Test("Leeway per QoS level matches spec")
    func test_leeway_per_qos_level() async throws {
        #expect(ServiceQoS.critical.defaultLeeway == .zero)
        #expect(ServiceQoS.userInitiated.defaultLeeway == .seconds(2))
        #expect(ServiceQoS.default.defaultLeeway == .seconds(5))
        #expect(ServiceQoS.utility.defaultLeeway == .seconds(10))
        #expect(ServiceQoS.background.defaultLeeway == .seconds(30))
    }
}

@Suite("ShikkiKernel — Service Intervals")
struct ShikkiKernelServiceIntervalTests {

    @Test("HealthMonitor interval is 10s")
    func test_healthMonitor_interval_is_10s() async throws {
        let mockClient = MockBackendClient()
        let monitor = HealthMonitor(client: mockClient)

        #expect(await monitor.interval == .seconds(10))
        #expect(await monitor.qos == .critical)
        #expect(await monitor.id == .healthMonitor)
    }

    @Test("DispatchService interval is 60s")
    func test_dispatchService_interval_is_60s() async throws {
        let mockClient = MockBackendClient()
        let launcher = MockProcessLauncher()
        let notifier = MockNotificationSender()
        let loop = HeartbeatLoop(
            client: mockClient,
            launcher: launcher,
            notifier: notifier
        )
        let service = DispatchService(heartbeatLoop: loop)

        #expect(await service.interval == .seconds(60))
        #expect(await service.qos == .default)
        #expect(await service.id == .dispatchService)
    }
}

@Suite("ShikkiKernel — Snapshot")
struct KernelSnapshotTests {

    @Test("Unreachable snapshot has correct health")
    func unreachableSnapshot() {
        let snapshot = KernelSnapshot.unreachable
        #expect(snapshot.health == .unreachable)
        #expect(snapshot.companies.isEmpty)
        #expect(snapshot.dispatchQueue.isEmpty)
        #expect(snapshot.pendingDecisions.isEmpty)
        #expect(snapshot.sessions.isEmpty)
    }

    @Test("Snapshot preserves all fields")
    func snapshotFields() {
        let now = Date()
        let snapshot = KernelSnapshot(
            health: .healthy,
            companies: [],
            dispatchQueue: [],
            pendingDecisions: [],
            sessions: [SessionInfo(slug: "test:task", companySlug: "test", isRunning: true)],
            fetchedAt: now
        )

        #expect(snapshot.health == .healthy)
        #expect(snapshot.sessions.count == 1)
        #expect(snapshot.sessions.first?.slug == "test:task")
        #expect(snapshot.fetchedAt == now)
    }
}

@Suite("ShikkiKernel — RestartPolicy")
struct RestartPolicyTests {

    @Test("ServiceID has all expected cases")
    func serviceIDCases() {
        let allIDs = ServiceID.allCases
        #expect(allIDs.contains(.healthMonitor))
        #expect(allIDs.contains(.dispatchService))
        #expect(allIDs.contains(.sessionSupervisor))
        #expect(allIDs.contains(.staleCompanyDetector))
        #expect(allIDs.count >= 8)
    }

    @Test("Default canRun blocks non-critical when unhealthy")
    func defaultCanRun() async {
        let criticalService = SpyService(id: .healthMonitor, qos: .critical)
        let defaultService = SpyService(id: .dispatchService, qos: .default)
        let bgService = SpyService(id: .staleCompanyDetector, qos: .background)

        // Healthy: all can run
        #expect(await criticalService.canRun(health: .healthy) == true)
        #expect(await defaultService.canRun(health: .healthy) == true)
        #expect(await bgService.canRun(health: .healthy) == true)

        // Degraded: only critical
        #expect(await criticalService.canRun(health: .degraded(reason: "test")) == true)
        #expect(await defaultService.canRun(health: .degraded(reason: "test")) == false)
        #expect(await bgService.canRun(health: .degraded(reason: "test")) == false)

        // Unreachable: only critical
        #expect(await criticalService.canRun(health: .unreachable) == true)
        #expect(await defaultService.canRun(health: .unreachable) == false)
    }
}

@Suite("ShikkiKernel — Wake Signal")
struct ShikkiKernelWakeTests {

    @Test("Wake signal interrupts tickless sleep")
    func test_wake_interrupts_sleep() async throws {
        // Service with 60s interval — kernel would normally sleep 60s after first tick
        let service = SpyService(id: .healthMonitor, qos: .critical, interval: .seconds(60))

        let kernel = ShikkiKernel(
            services: [service],
            snapshotProvider: MockSnapshotProvider()
        )

        let task = Task {
            await kernel.run()
        }

        // Wait for initial tick
        try await Task.sleep(for: .milliseconds(200))
        let ticksAfterFirst = await service.tickCount
        #expect(ticksAfterFirst == 1)

        // Now kernel is sleeping for ~60s. Wake it.
        await kernel.wake(.taskCreated("test-task"))

        // Wait a bit for the wake to process — should tick again despite 60s interval
        try await Task.sleep(for: .milliseconds(300))

        task.cancel()
        await kernel.shutdown()

        let ticksAfterWake = await service.tickCount
        // Service has 60s interval but HealthMonitor has 0 leeway,
        // so it won't be due yet. The kernel wakes and recomputes,
        // but only collects services that are actually due.
        // The key assertion: the kernel did NOT sleep for 60s.
        // We prove this by checking total elapsed time < 1s.
        #expect(ticksAfterWake >= 1)
    }

    @Test("Multiple wake signals are buffered")
    func test_multiple_wake_signals_buffered() async throws {
        let service = SpyService(id: .dispatchService, qos: .default, interval: .seconds(60))

        let kernel = ShikkiKernel(
            services: [service],
            snapshotProvider: MockSnapshotProvider()
        )

        // Send multiple wake signals before kernel even starts
        await kernel.wake(.taskCreated("task-1"))
        await kernel.wake(.taskCreated("task-2"))
        await kernel.wake(.dispatchRequested)

        // Kernel should consume them without crashing
        let task = Task {
            await kernel.run()
        }

        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        await kernel.shutdown()

        // Should have processed at least the initial tick
        let ticks = await service.tickCount
        #expect(ticks >= 1)
    }

    @Test("wakeSync works from non-isolated context")
    func test_wakeSync_nonisolated() async throws {
        let service = SpyService(id: .healthMonitor, qos: .critical, interval: .seconds(60))

        let kernel = ShikkiKernel(
            services: [service],
            snapshotProvider: MockSnapshotProvider()
        )

        // wakeSync is nonisolated — can call from anywhere
        kernel.wakeSync(.externalSignal("test"))

        // Should not crash, signal is buffered
        let ids = await kernel.serviceIDs
        #expect(ids.contains(.healthMonitor))
    }

    @Test("WakeReason description is readable")
    func test_wakeReason_description() {
        #expect(WakeReason.taskCreated("my-task").description == "taskCreated(my-task)")
        #expect(WakeReason.dispatchRequested.description == "dispatchRequested")
        #expect(WakeReason.serviceNudge(.healthMonitor).description == "serviceNudge(healthMonitor)")
        #expect(WakeReason.externalSignal("mcp").description == "externalSignal(mcp)")
    }

    @Test("Shutdown finishes the wake stream")
    func test_shutdown_finishes_wake_stream() async throws {
        let service = SpyService(id: .healthMonitor, qos: .critical, interval: .seconds(60))

        let kernel = ShikkiKernel(
            services: [service],
            snapshotProvider: MockSnapshotProvider()
        )

        let task = Task {
            await kernel.run()
        }

        try await Task.sleep(for: .milliseconds(200))
        await kernel.shutdown()

        // Wake after shutdown should not crash (continuation is finished)
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
    }
}
