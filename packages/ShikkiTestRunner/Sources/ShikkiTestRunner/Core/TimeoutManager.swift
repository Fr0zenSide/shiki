// MARK: - TimeoutManager.swift
// ShikkiTestRunner — Per-test timeout tracking with async cancellation

import Foundation

/// Callback invoked when a test exceeds its timeout duration.
public typealias TimeoutHandler = @Sendable (String) async -> Void

/// Actor that manages per-test timeouts.
///
/// Each running test gets a timer. If `testPassed` / `testFailed` doesn't arrive
/// within the configured limit, the timeout fires and marks the test as timed out.
/// Inspired by LLVM lit's per-test timeout mechanism.
public actor TimeoutManager {

    /// Default timeout per test.
    public let defaultLimit: Duration

    /// Callback fired when a test times out. Receives the testID.
    private let onTimeout: TimeoutHandler

    /// Active timeout tasks keyed by testID.
    private var activeTasks: [String: Task<Void, Never>] = [:]

    /// Set of testIDs that have timed out (for query).
    private var timedOut: Set<String> = []

    /// Number of currently active (running) timeouts.
    public var activeCount: Int {
        activeTasks.count
    }

    /// Returns the set of test IDs that have timed out.
    public var timedOutTests: Set<String> {
        timedOut
    }

    /// Initialize with a default timeout and a handler for timed-out tests.
    ///
    /// - Parameters:
    ///   - defaultLimit: Per-test timeout duration (default 5 seconds).
    ///   - onTimeout: Called with the testID when timeout fires.
    public init(
        defaultLimit: Duration = .seconds(5),
        onTimeout: @escaping TimeoutHandler
    ) {
        self.defaultLimit = defaultLimit
        self.onTimeout = onTimeout
    }

    /// Start a timeout timer for the given test.
    ///
    /// If a timeout already exists for this testID, it is cancelled and replaced.
    ///
    /// - Parameters:
    ///   - testID: Unique identifier for the test.
    ///   - limit: Override the default timeout for this specific test.
    public func startTimeout(testID: String, limit: Duration? = nil) {
        activeTasks[testID]?.cancel()

        let duration = limit ?? defaultLimit
        let handler = onTimeout

        let task = Task { [weak self] in
            do {
                try await Task.sleep(for: duration)
                guard let self else { return }
                await self.markTimedOut(testID)
                await handler(testID)
            } catch {
                // Task was cancelled — test completed before timeout
            }
        }

        activeTasks[testID] = task
    }

    /// Cancel the timeout for a test (called on pass/fail).
    ///
    /// - Parameter testID: The test whose timeout should be cancelled.
    public func cancelTimeout(testID: String) {
        activeTasks[testID]?.cancel()
        activeTasks.removeValue(forKey: testID)
    }

    /// Cancel all active timeouts.
    public func cancelAll() {
        for (_, task) in activeTasks {
            task.cancel()
        }
        activeTasks.removeAll()
    }

    /// Check whether a specific test has timed out.
    public func hasTimedOut(testID: String) -> Bool {
        timedOut.contains(testID)
    }

    // MARK: - Private

    private func markTimedOut(_ testID: String) {
        timedOut.insert(testID)
        activeTasks.removeValue(forKey: testID)
    }
}
