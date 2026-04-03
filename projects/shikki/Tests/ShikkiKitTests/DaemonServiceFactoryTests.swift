import Foundation
import Testing
@testable import ShikkiKit

@Suite("DaemonServiceFactory")
struct DaemonServiceFactoryTests {

    private let config = DaemonConfig()

    @Test("createPersistentServices returns 6 services")
    func persistentServices_count() {
        let services = DaemonServiceFactory.createPersistentServices(config: config)
        #expect(services.count == 6)
    }

    @Test("createScheduledServices returns 2 services")
    func scheduledServices_count() {
        let services = DaemonServiceFactory.createScheduledServices(config: config)
        #expect(services.count == 2)
    }

    @Test("persistent set includes .natsServer")
    func persistentServices_includesNatsServer() {
        let services = DaemonServiceFactory.createPersistentServices(config: config)
        let ids = services.map(\.id)
        #expect(ids.contains(.natsServer))
    }

    @Test("scheduled set does NOT include .natsServer")
    func scheduledServices_excludesNatsServer() {
        let services = DaemonServiceFactory.createScheduledServices(config: config)
        let ids = services.map(\.id)
        #expect(!ids.contains(.natsServer))
    }

    @Test("persistent set includes all expected service IDs")
    func persistentServices_expectedIDs() {
        let services = DaemonServiceFactory.createPersistentServices(config: config)
        let ids = Set(services.map(\.id))
        let expected: Set<ServiceID> = [
            .natsServer,
            .healthMonitor,
            .eventPersister,
            .sessionSupervisor,
            .staleCompanyDetector,
            .taskScheduler,
        ]
        #expect(ids == expected)
    }

    @Test("scheduled set includes expected service IDs")
    func scheduledServices_expectedIDs() {
        let services = DaemonServiceFactory.createScheduledServices(config: config)
        let ids = Set(services.map(\.id))
        let expected: Set<ServiceID> = [
            .taskScheduler,
            .staleCompanyDetector,
        ]
        #expect(ids == expected)
    }

    @Test("all persistent services have unique IDs")
    func persistentServices_uniqueIDs() {
        let services = DaemonServiceFactory.createPersistentServices(config: config)
        let ids = services.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("DaemonConfig defaults")
    func daemonConfig_defaults() {
        let config = DaemonConfig()
        #expect(config.natsURL == "nats://localhost:4222")
        #expect(config.backendURL == "http://localhost:3900")
    }

    @Test("DaemonConfig custom values")
    func daemonConfig_custom() {
        let config = DaemonConfig(
            natsURL: "nats://prod:4222",
            backendURL: "http://prod:3900",
            workspacePath: "/opt/shikki"
        )
        #expect(config.natsURL == "nats://prod:4222")
        #expect(config.backendURL == "http://prod:3900")
        #expect(config.workspacePath == "/opt/shikki")
    }
}
