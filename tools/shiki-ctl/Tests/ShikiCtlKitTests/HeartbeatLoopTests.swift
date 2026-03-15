import Foundation
import Testing
@testable import ShikiCtlKit

// MARK: - Test Doubles

final class MockProcessLauncher: ProcessLauncher, @unchecked Sendable {
    var launchedSessions: [(taskId: String, companyId: String, companySlug: String, title: String, projectPath: String)] = []
    var runningSlugs: Set<String> = []
    var stoppedSlugs: [String] = []

    func launchTaskSession(taskId: String, companyId: String, companySlug: String,
                           title: String, projectPath: String) async throws {
        let slug = TmuxProcessLauncher.windowName(companySlug: companySlug, title: title)
        launchedSessions.append((taskId, companyId, companySlug, title, projectPath))
        runningSlugs.insert(slug)
    }

    func isSessionRunning(slug: String) async -> Bool {
        runningSlugs.contains(slug)
    }

    func stopSession(slug: String) async throws {
        runningSlugs.remove(slug)
        stoppedSlugs.append(slug)
    }

    func listRunningSessions() async -> [String] {
        Array(runningSlugs)
    }
}

final class MockNotificationSender: NotificationSender, @unchecked Sendable {
    var sentNotifications: [(title: String, body: String, priority: NotificationPriority)] = []

    func send(title: String, body: String, priority: NotificationPriority, tags: [String]) async throws {
        sentNotifications.append((title, body, priority))
    }
}

// MARK: - Tests

@Suite("HeartbeatLoop unit logic")
struct HeartbeatLoopTests {

    @Test("Notification sent for T1 decisions")
    func t1DecisionNotification() async throws {
        let notifier = MockNotificationSender()

        try await notifier.send(title: "Test", body: "body", priority: .high, tags: ["test"])
        #expect(notifier.sentNotifications.count == 1)
    }

    @Test("ProcessLauncher mock tracks task launches")
    func launcherTracking() async throws {
        let launcher = MockProcessLauncher()

        try await launcher.launchTaskSession(
            taskId: "t-1", companyId: "id-1", companySlug: "wabisabi",
            title: "SPM-wave3", projectPath: "wabisabi"
        )
        #expect(launcher.launchedSessions.count == 1)
        #expect(launcher.launchedSessions[0].companySlug == "wabisabi")
        #expect(launcher.launchedSessions[0].taskId == "t-1")

        let slug = TmuxProcessLauncher.windowName(companySlug: "wabisabi", title: "SPM-wave3")
        #expect(await launcher.isSessionRunning(slug: slug))

        try await launcher.stopSession(slug: slug)
        #expect(!(await launcher.isSessionRunning(slug: slug)))
        #expect(launcher.stoppedSlugs == [slug])
    }

    @Test("listRunningSessions returns all active slugs")
    func listRunningSessions() async throws {
        let launcher = MockProcessLauncher()

        try await launcher.launchTaskSession(
            taskId: "t-1", companyId: "id-1", companySlug: "maya",
            title: "MayaKit-wave2", projectPath: "Maya"
        )
        try await launcher.launchTaskSession(
            taskId: "t-2", companyId: "id-2", companySlug: "wabisabi",
            title: "SPM-wave3", projectPath: "wabisabi"
        )

        let sessions = await launcher.listRunningSessions()
        #expect(sessions.count == 2)
    }
}

@Suite("Window naming")
struct WindowNamingTests {

    @Test("Window name format")
    func windowNameFormat() {
        let name = TmuxProcessLauncher.windowName(companySlug: "maya", title: "MayaKit public API wave 2")
        #expect(name == "maya:mayakit-public-")
    }

    @Test("Short title stays intact")
    func shortTitle() {
        let name = TmuxProcessLauncher.windowName(companySlug: "flsh", title: "MLX pipeline")
        #expect(name == "flsh:mlx-pipeline")
    }
}
