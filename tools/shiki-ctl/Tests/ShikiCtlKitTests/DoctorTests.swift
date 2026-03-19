import Foundation
import Testing
@testable import ShikiCtlKit

@Suite("Shiki Doctor diagnostics")
struct DoctorTests {

    @Test("PATH check detects required binaries")
    func pathCheck() async {
        let doctor = ShikiDoctor()
        let result = await doctor.checkBinary("git")
        #expect(result.status == .ok)
        #expect(result.category == .binary)
    }

    @Test("Missing optional binary reports warning")
    func missingOptionalBinary() async {
        let doctor = ShikiDoctor()
        let result = await doctor.checkBinary("nonexistent-xyz-12345")
        #expect(result.status == .warning)
        #expect(result.message.contains("not found"))
    }

    @Test("All diagnostic categories covered")
    func allCategories() {
        let categories = DiagnosticCategory.allCases
        #expect(categories.count == 7)
        #expect(categories.contains(.binary))
        #expect(categories.contains(.docker))
        #expect(categories.contains(.backend))
        #expect(categories.contains(.sessions))
        #expect(categories.contains(.config))
        #expect(categories.contains(.disk))
        #expect(categories.contains(.git))
    }

    @Test("Diagnostic result has name and message")
    func diagnosticResult() {
        let result = DiagnosticResult(
            name: "tmux", category: .binary,
            status: .ok, message: "tmux 3.4 found"
        )
        #expect(result.name == "tmux")
        #expect(result.message == "tmux 3.4 found")
    }

    @Test("Status severity ordering")
    func statusOrdering() {
        #expect(DiagnosticStatus.ok.severity < DiagnosticStatus.warning.severity)
        #expect(DiagnosticStatus.warning.severity < DiagnosticStatus.error.severity)
    }
}

@Suite("Dashboard data model")
struct DashboardModelTests {

    @Test("DashboardSnapshot from registry")
    func snapshotFromRegistry() async {
        let discoverer = MockSessionDiscoverer()
        let journal = SessionJournal(basePath: NSTemporaryDirectory() + "shiki-dash-\(UUID().uuidString)")
        let registry = SessionRegistry(discoverer: discoverer, journal: journal)

        await registry.registerManual(windowName: "maya:task", paneId: "%1", pid: 1, state: .working)
        await registry.registerManual(windowName: "wabi:pr", paneId: "%2", pid: 2, state: .approved)

        let snapshot = await DashboardSnapshot.from(registry: registry)
        #expect(snapshot.sessions.count == 2)
        #expect(snapshot.sessions[0].attentionZone == .merge) // approved = merge, sorted first
        #expect(snapshot.sessions[1].attentionZone == .working)
    }

    @Test("Snapshot is Codable")
    func snapshotCodable() throws {
        let snapshot = DashboardSnapshot(
            sessions: [
                DashboardSession(windowName: "test", state: .working, attentionZone: .working, companySlug: "test"),
            ],
            timestamp: Date()
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(DashboardSnapshot.self, from: data)
        #expect(decoded.sessions.count == 1)
    }
}
