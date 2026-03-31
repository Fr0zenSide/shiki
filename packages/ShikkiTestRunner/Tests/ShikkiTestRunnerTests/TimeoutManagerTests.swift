// MARK: - TimeoutManagerTests.swift
// ShikkiTestRunner — Tests for per-test timeout tracking

import Foundation
import Testing

@testable import ShikkiTestRunner

@Suite("TimeoutManager")
struct TimeoutManagerTests {

    // MARK: - Timeout Fires

    @Test("Timeout fires after duration elapses")
    func timeoutFires() async throws {
        let box = ActorBox<[String]>([])

        let manager = TimeoutManager(defaultLimit: .milliseconds(50)) { testID in
            await box.append(testID)
        }

        await manager.startTimeout(testID: "T/slow")

        // Wait long enough for timeout to fire
        try await Task.sleep(for: .milliseconds(200))

        let timedOut = await manager.hasTimedOut(testID: "T/slow")
        #expect(timedOut == true)

        let fired = await box.get()
        #expect(fired == ["T/slow"])
    }

    // MARK: - Cancel Prevents Timeout

    @Test("Cancel prevents timeout from firing")
    func cancelPreventsTimeout() async throws {
        let box = ActorBox<[String]>([])

        let manager = TimeoutManager(defaultLimit: .milliseconds(100)) { testID in
            await box.append(testID)
        }

        await manager.startTimeout(testID: "T/fast")
        // Cancel before timeout fires
        await manager.cancelTimeout(testID: "T/fast")

        // Wait past the timeout duration
        try await Task.sleep(for: .milliseconds(200))

        let timedOut = await manager.hasTimedOut(testID: "T/fast")
        #expect(timedOut == false)
        let fired = await box.get()
        #expect(fired.isEmpty)
    }

    // MARK: - Multiple Concurrent Timeouts

    @Test("Multiple concurrent timeouts tracked independently")
    func multipleConcurrent() async throws {
        let box = ActorBox<[String]>([])

        let manager = TimeoutManager(defaultLimit: .milliseconds(50)) { testID in
            await box.append(testID)
        }

        // Start two timeouts
        await manager.startTimeout(testID: "T/a")
        await manager.startTimeout(testID: "T/b")

        // Cancel only one
        await manager.cancelTimeout(testID: "T/a")

        // Wait for timeout to fire
        try await Task.sleep(for: .milliseconds(200))

        let aTimedOut = await manager.hasTimedOut(testID: "T/a")
        let bTimedOut = await manager.hasTimedOut(testID: "T/b")
        #expect(aTimedOut == false)
        #expect(bTimedOut == true)

        let fired = await box.get()
        #expect(fired == ["T/b"])
    }

    // MARK: - Active Count

    @Test("Active count tracks running timeouts")
    func activeCount() async throws {
        let manager = TimeoutManager(defaultLimit: .seconds(10)) { _ in }

        await manager.startTimeout(testID: "T/1")
        await manager.startTimeout(testID: "T/2")
        await manager.startTimeout(testID: "T/3")

        let count = await manager.activeCount
        #expect(count == 3)

        await manager.cancelTimeout(testID: "T/2")

        let afterCancel = await manager.activeCount
        #expect(afterCancel == 2)
    }

    // MARK: - Cancel All

    @Test("Cancel all clears all active timeouts")
    func cancelAll() async throws {
        let manager = TimeoutManager(defaultLimit: .seconds(10)) { _ in }

        await manager.startTimeout(testID: "T/1")
        await manager.startTimeout(testID: "T/2")

        await manager.cancelAll()

        let count = await manager.activeCount
        #expect(count == 0)

        // Wait and verify nothing fires
        try await Task.sleep(for: .milliseconds(50))
        let set = await manager.timedOutTests
        #expect(set.isEmpty)
    }

    // MARK: - Custom Per-Test Limit

    @Test("Custom per-test limit overrides default")
    func customLimit() async throws {
        let manager = TimeoutManager(defaultLimit: .seconds(10)) { _ in }

        // Use very short custom limit
        await manager.startTimeout(testID: "T/custom", limit: .milliseconds(50))

        try await Task.sleep(for: .milliseconds(200))

        let timedOut = await manager.hasTimedOut(testID: "T/custom")
        #expect(timedOut == true)
    }

    // MARK: - Restart Timeout

    @Test("Starting timeout for same test replaces the previous one")
    func restartTimeout() async throws {
        let manager = TimeoutManager(defaultLimit: .milliseconds(200)) { _ in }

        await manager.startTimeout(testID: "T/retry")

        // Replace with shorter timeout
        await manager.startTimeout(testID: "T/retry", limit: .milliseconds(30))

        // Active count should still be 1
        let count = await manager.activeCount
        #expect(count == 1)
    }

    // MARK: - Timed Out Tests Set

    @Test("timedOutTests returns all timed-out test IDs")
    func timedOutTestsSet() async throws {
        let manager = TimeoutManager(defaultLimit: .milliseconds(30)) { _ in }

        await manager.startTimeout(testID: "T/a")
        await manager.startTimeout(testID: "T/b")
        await manager.cancelTimeout(testID: "T/b")

        try await Task.sleep(for: .milliseconds(150))

        let set = await manager.timedOutTests
        #expect(set.contains("T/a"))
        #expect(!set.contains("T/b"))
    }
}

// MARK: - Helpers

/// A simple actor-isolated box for collecting values in async callbacks.
private actor ActorBox<T> {
    var value: T

    init(_ initial: T) {
        self.value = initial
    }

    func append(_ element: String) where T == [String] {
        value.append(element)
    }

    func get() -> T {
        value
    }
}
