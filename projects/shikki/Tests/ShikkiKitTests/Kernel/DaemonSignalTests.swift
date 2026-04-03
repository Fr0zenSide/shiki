import Foundation
import Testing
@testable import ShikkiKit

@Suite("DaemonSignalHandler")
struct DaemonSignalTests {

    @Test("Signal handler can be installed without crash")
    func installWithoutCrash() {
        // Installing signal handlers should not throw or crash.
        // We use no-op closures since we cannot actually send signals in tests.
        DaemonSignalHandler.install(
            onShutdown: {},
            onReload: {}
        )
        // If we reach here, installation succeeded.
        #expect(true)
    }

    @Test("onShutdown callback type is @Sendable () -> Void")
    func shutdownCallbackIsSendable() {
        // Verify that the API accepts @Sendable closures.
        let flag = LockedFlag()
        DaemonSignalHandler.install(
            onShutdown: { flag.set() },
            onReload: {}
        )
        #expect(!flag.isSet)
    }

    @Test("onReload callback type is @Sendable () -> Void")
    func reloadCallbackIsSendable() {
        let flag = LockedFlag()
        DaemonSignalHandler.install(
            onShutdown: {},
            onReload: { flag.set() }
        )
        #expect(!flag.isSet)
    }

    @Test("Multiple install calls do not crash")
    func multipleInstalls() {
        for _ in 0..<5 {
            DaemonSignalHandler.install(
                onShutdown: {},
                onReload: {}
            )
        }
        #expect(true)
    }
}

// MARK: - LockedFlag

/// Thread-safe boolean flag for testing signal callbacks.
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func set() {
        lock.lock()
        defer { lock.unlock() }
        _value = true
    }
}
