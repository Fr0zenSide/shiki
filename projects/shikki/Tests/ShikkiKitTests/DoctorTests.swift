import Foundation
import Testing
@testable import ShikkiKit

@Suite("Shiki Doctor diagnostics")
struct DoctorTests {

    @Test("PATH check detects required binaries")
    func pathCheck() async {
        let doctor = ShikkiDoctor()
        let result = await doctor.checkBinary("git")
        #expect(result.status == .ok)
        #expect(result.category == .binary)
    }

    @Test("Missing optional binary reports warning")
    func missingOptionalBinary() async {
        let doctor = ShikkiDoctor()
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

// DashboardModelTests — extracted to plugins/shikki-dashboard/Tests/
