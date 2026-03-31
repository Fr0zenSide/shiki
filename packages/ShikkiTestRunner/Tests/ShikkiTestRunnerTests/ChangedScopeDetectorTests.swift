import Foundation
import Testing

@testable import ShikkiTestRunner

@Suite("ChangedScopeDetector")
struct ChangedScopeDetectorTests {

    // MARK: - Helpers

    private static let testManifest = ScopeManifest(
        scopes: [
            ScopeDefinition(
                name: "nats",
                modulePatterns: ["NATSClient", "NATSProtocol"],
                typePatterns: ["NATSConnection", "EventBus", "EventRouter"],
                testFilePatterns: ["**/NATS*Tests.swift", "**/EventBus*Tests.swift"]
            ),
            ScopeDefinition(
                name: "kernel",
                modulePatterns: ["ShikkiKit"],
                typePatterns: ["ShikkiKernel", "ManagedService", "ServiceLifecycle"],
                testFilePatterns: ["**/Kernel*Tests.swift"]
            ),
            ScopeDefinition(
                name: "tui",
                modulePatterns: ["TUI"],
                typePatterns: ["TerminalOutput", "ANSIRenderer"],
                testFilePatterns: ["**/TUI*Tests.swift"],
                dependsOn: ["kernel"]
            ),
            ScopeDefinition(
                name: "observatory",
                modulePatterns: ["Observatory"],
                typePatterns: ["DecisionJournal", "AgentReportCard"],
                testFilePatterns: ["**/Observatory*Tests.swift"],
                dependsOn: ["nats"]
            ),
            ScopeDefinition(
                name: "ship",
                modulePatterns: ["Ship"],
                typePatterns: ["ShipGate", "VersionBumper"],
                testFilePatterns: ["**/Ship*Tests.swift"],
                dependsOn: ["kernel", "safety"]
            ),
            ScopeDefinition(
                name: "safety",
                modulePatterns: ["Safety"],
                typePatterns: ["BudgetACL", "AuditLogger"],
                testFilePatterns: ["**/Safety*Tests.swift"]
            ),
        ],
        source: .defaultFallback
    )

    private var detector: ChangedScopeDetector {
        ChangedScopeDetector(manifest: Self.testManifest)
    }

    // MARK: - Direct Scope Detection

    @Test("Detect scope from test file pattern")
    func detectFromTestFilePattern() {
        let affected = detector.affectedScopes(
            changedFiles: ["Tests/ShikkiKitTests/NATSConnectionTests.swift"]
        )
        let names = affected.map(\.name)
        #expect(names == ["nats"])
    }

    @Test("Detect scope from source file with type name")
    func detectFromSourceTypeFile() {
        let affected = detector.affectedScopes(
            changedFiles: ["Sources/ShikkiKit/Services/EventBus.swift"]
        )
        let names = affected.map(\.name)
        #expect(names == ["nats"])
    }

    @Test("Detect scope from module directory path")
    func detectFromModulePath() {
        let affected = detector.affectedScopes(
            changedFiles: ["Sources/ShikkiKit/Models/SomeModel.swift"]
        )
        let names = affected.map(\.name)
        #expect(names == ["kernel"])
    }

    @Test("Detect scope from directory name matching scope")
    func detectFromDirectoryName() {
        let affected = detector.affectedScopes(
            changedFiles: ["Sources/Observatory/ReportCard.swift"]
        )
        let names = affected.map(\.name)
        #expect(names == ["observatory"])
    }

    @Test("Multiple changed files affect multiple scopes")
    func multipleFilesMultipleScopes() {
        let affected = detector.affectedScopes(
            changedFiles: [
                "Sources/ShikkiKit/Services/EventBus.swift",
                "Sources/ShikkiKit/Kernel/ShikkiKernel.swift",
                "Tests/TUIRenderTests.swift",
            ]
        )
        let names = affected.map(\.name)
        // nats (EventBus), kernel (ShikkiKernel), tui (test file pattern)
        #expect(names.contains("nats"))
        #expect(names.contains("kernel"))
        #expect(names.contains("tui"))
    }

    @Test("Unrecognized files return empty scopes")
    func unrecognizedFilesEmpty() {
        let affected = detector.affectedScopes(
            changedFiles: ["README.md", "Package.swift", ".gitignore"]
        )
        #expect(affected.isEmpty)
    }

    @Test("De-duplicates scopes from multiple files in same scope")
    func deduplicatesSameScope() {
        let affected = detector.affectedScopes(
            changedFiles: [
                "Sources/NATSClient/Connection.swift",
                "Tests/NATSConnectionTests.swift",
                "Sources/NATSClient/Subscription.swift",
            ]
        )
        let names = affected.map(\.name)
        #expect(names == ["nats"])
    }

    @Test("Empty changed files returns empty scopes")
    func emptyChangedFiles() {
        let affected = detector.affectedScopes(changedFiles: [])
        #expect(affected.isEmpty)
    }

    // MARK: - Dependency Expansion

    @Test("Expand includes direct dependents")
    func expandDirectDependents() {
        // Change kernel → should also include tui (depends on kernel) and ship (depends on kernel)
        let affected = detector.affectedWithDeps(
            changedFiles: ["Sources/ShikkiKit/Kernel/ShikkiKernel.swift"]
        )
        let names = affected.map(\.name)
        #expect(names.contains("kernel"))
        #expect(names.contains("tui"))    // depends on kernel
        #expect(names.contains("ship"))   // depends on kernel
    }

    @Test("Expand includes transitive dependents")
    func expandTransitiveDependents() {
        // Change safety → ship depends on safety → but nothing depends on ship
        let affected = detector.affectedWithDeps(
            changedFiles: ["Sources/Safety/BudgetACL.swift"]
        )
        let names = affected.map(\.name)
        #expect(names.contains("safety"))
        #expect(names.contains("ship"))  // depends on safety
    }

    @Test("No deps expansion when scope has no dependents")
    func noDepsExpansion() {
        // Change tui → nothing depends on tui
        let affected = detector.affectedWithDeps(
            changedFiles: ["Tests/TUIRenderTests.swift"]
        )
        let names = affected.map(\.name)
        #expect(names == ["tui"])
    }

    @Test("Preserve manifest order in expansion output")
    func preserveOrderInExpansion() {
        // nats changed → observatory depends on nats
        let affected = detector.affectedWithDeps(
            changedFiles: ["Sources/NATSClient/EventBus.swift"]
        )
        let names = affected.map(\.name)
        // nats is before observatory in manifest order
        if let natsIdx = names.firstIndex(of: "nats"),
           let obsIdx = names.firstIndex(of: "observatory") {
            #expect(natsIdx < obsIdx)
        } else {
            Issue.record("Expected both nats and observatory in results")
        }
    }

    // MARK: - Edge Cases

    @Test("Scope name extraction utility")
    func scopeNameExtraction() {
        let scopes = [
            ScopeDefinition(name: "a", modulePatterns: ["A"]),
            ScopeDefinition(name: "b", modulePatterns: ["B"]),
        ]
        let names = ChangedScopeDetector.scopeNames(from: scopes)
        #expect(names == ["a", "b"])
    }
}
